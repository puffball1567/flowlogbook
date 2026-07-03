import std/strutils

import ./decision
import ./fingerprint
import ./jsonio
import ./types
import ./validation

type
  PostgresLedger* = object
    conn: pointer

const
  ConnectionOk = 0.cint
  PgCommandOk = 1.cint
  PgTuplesOk = 2.cint
  PgDynlib =
    when defined(windows):
      "libpq.dll"
    elif defined(macosx):
      "libpq.dylib"
    else:
      "libpq.so"
  SchemaVersion* = 1

proc PQconnectdb(conninfo: cstring): pointer {.importc, cdecl, dynlib: PgDynlib.}
proc PQfinish(conn: pointer) {.importc, cdecl, dynlib: PgDynlib.}
proc PQstatus(conn: pointer): cint {.importc, cdecl, dynlib: PgDynlib.}
proc PQerrorMessage(conn: pointer): cstring {.importc, cdecl, dynlib: PgDynlib.}
proc PQexec(conn: pointer; command: cstring): pointer {.importc, cdecl, dynlib: PgDynlib.}
proc PQexecParams(conn: pointer; command: cstring; nParams: cint;
    paramTypes: pointer; paramValues: ptr cstring; paramLengths: pointer;
    paramFormats: pointer; resultFormat: cint): pointer
    {.importc, cdecl, dynlib: PgDynlib.}
proc PQresultStatus(res: pointer): cint {.importc, cdecl, dynlib: PgDynlib.}
proc PQntuples(res: pointer): cint {.importc, cdecl, dynlib: PgDynlib.}
proc PQgetvalue(res: pointer; tupNum, fieldNum: cint): cstring
    {.importc, cdecl, dynlib: PgDynlib.}
proc PQclear(res: pointer) {.importc, cdecl, dynlib: PgDynlib.}

proc pgError(conn: pointer; prefix: string): ref ValueError =
  newException(ValueError, prefix & ": " & $PQerrorMessage(conn))

proc checkResult(conn: pointer; res: pointer; expected: openArray[cint];
    prefix: string) =
  if res.isNil:
    raise pgError(conn, prefix)
  let status = PQresultStatus(res)
  for item in expected:
    if status == item:
      return
  raise pgError(conn, prefix)

proc execCommand(conn: pointer; sql: string) =
  let res = PQexec(conn, sql.cstring)
  try:
    checkResult(conn, res, [PgCommandOk], "postgres command failed")
  finally:
    if not res.isNil:
      PQclear(res)

proc execParams(conn: pointer; sql: string; params: openArray[string];
    expected: openArray[cint]; prefix: string): pointer =
  var values = newSeq[cstring](params.len)
  for i, value in params:
    values[i] = value.cstring
  let valuePtr =
    if values.len == 0:
      nil
    else:
      addr values[0]
  let res = PQexecParams(conn, sql.cstring, cint(values.len), nil, valuePtr,
    nil, nil, 0)
  checkResult(conn, res, expected, prefix)
  res

proc columnString(res: pointer; row, col: int): string =
  $PQgetvalue(res, cint(row), cint(col))

proc initSchema(conn: pointer) =
  execCommand(conn, """
CREATE TABLE IF NOT EXISTS flowlogbook_schema (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL
);
INSERT INTO flowlogbook_schema (id, version)
VALUES (1, 1)
ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS flowlogbook_run_records (
  id BIGSERIAL PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt BIGINT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_run_records_fingerprint_id
  ON flowlogbook_run_records(fingerprint, id);
CREATE TABLE IF NOT EXISTS flowlogbook_flow_events (
  seq BIGSERIAL PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL,
  flow_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  variant_id TEXT NOT NULL,
  node_id TEXT NOT NULL,
  edge_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  duration_millis BIGINT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_flow_id
  ON flowlogbook_flow_events(flow_id);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_run_id
  ON flowlogbook_flow_events(run_id);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_variant_id
  ON flowlogbook_flow_events(variant_id);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_node_id
  ON flowlogbook_flow_events(node_id);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_edge_id
  ON flowlogbook_flow_events(edge_id);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_source
  ON flowlogbook_flow_events(source);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_kind
  ON flowlogbook_flow_events(kind);
CREATE INDEX IF NOT EXISTS idx_flowlogbook_flow_events_status
  ON flowlogbook_flow_events(status);
""")

proc schemaVersion*(ledger: PostgresLedger): int =
  let res = execParams(ledger.conn,
    "SELECT version FROM flowlogbook_schema WHERE id = 1",
    [], [PgTuplesOk], "postgres select schema version failed")
  try:
    if PQntuples(res) == 0:
      raise newException(ValueError, "postgres schema version is missing")
    parseInt(columnString(res, 0, 0))
  finally:
    PQclear(res)

proc openPostgresLedger*(conninfo: string): PostgresLedger =
  let conn = PQconnectdb(conninfo.cstring)
  if conn.isNil:
    raise newException(ValueError, "postgres connect failed")
  if PQstatus(conn) != ConnectionOk:
    let message = $PQerrorMessage(conn)
    PQfinish(conn)
    raise newException(ValueError, "postgres connect failed: " & message)
  try:
    initSchema(conn)
  except:
    PQfinish(conn)
    raise
  PostgresLedger(conn: conn)

proc close*(ledger: var PostgresLedger) =
  if not ledger.conn.isNil:
    PQfinish(ledger.conn)
    ledger.conn = nil

proc beginTransaction*(ledger: PostgresLedger) =
  execCommand(ledger.conn, "BEGIN")

proc commitTransaction*(ledger: PostgresLedger) =
  execCommand(ledger.conn, "COMMIT")

proc rollbackTransaction*(ledger: PostgresLedger) =
  execCommand(ledger.conn, "ROLLBACK")

proc record*(ledger: PostgresLedger; record: RunRecord) =
  requireValid(record)
  let res = execParams(ledger.conn,
    "INSERT INTO flowlogbook_run_records (fingerprint, status, attempt, json) VALUES ($1, $2, $3, $4)",
    [record.fingerprint, $record.status, $record.attempt, toJsonString(record)],
    [PgCommandOk], "postgres insert run record failed")
  PQclear(res)

proc contains*(ledger: PostgresLedger; fingerprint: string): bool =
  let res = execParams(ledger.conn,
    "SELECT 1 FROM flowlogbook_run_records WHERE fingerprint = $1 LIMIT 1",
    [fingerprint], [PgTuplesOk], "postgres select contains failed")
  try:
    PQntuples(res) > 0
  finally:
    PQclear(res)

proc history*(ledger: PostgresLedger; fingerprint: string): seq[RunRecord] =
  let res = execParams(ledger.conn,
    "SELECT json FROM flowlogbook_run_records WHERE fingerprint = $1 ORDER BY id ASC",
    [fingerprint], [PgTuplesOk], "postgres select run history failed")
  try:
    for i in 0 ..< int(PQntuples(res)):
      result.add(runRecordFromJsonString(columnString(res, i, 0)))
  finally:
    PQclear(res)

proc get*(ledger: PostgresLedger; fingerprint: string): RunRecord =
  let res = execParams(ledger.conn,
    "SELECT json FROM flowlogbook_run_records WHERE fingerprint = $1 ORDER BY id DESC LIMIT 1",
    [fingerprint], [PgTuplesOk], "postgres select latest run record failed")
  try:
    if PQntuples(res) == 0:
      raise newException(KeyError, "run record not found: " & fingerprint)
    runRecordFromJsonString(columnString(res, 0, 0))
  finally:
    PQclear(res)

proc attempts*(ledger: PostgresLedger; fingerprint: string): int =
  let res = execParams(ledger.conn,
    "SELECT COUNT(*) FROM flowlogbook_run_records WHERE fingerprint = $1",
    [fingerprint], [PgTuplesOk], "postgres count attempts failed")
  try:
    parseInt(columnString(res, 0, 0))
  finally:
    PQclear(res)

proc recordEvent*(ledger: PostgresLedger; event: FlowEvent) =
  requireValid(event)
  let res = execParams(ledger.conn, """
INSERT INTO flowlogbook_flow_events (
  id, source, flow_id, run_id, variant_id, node_id, edge_id, kind, status,
  duration_millis, json
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
""", [event.id, event.source, event.flowId, event.runId, event.variantId,
    event.nodeId, event.edgeId, $event.kind, $event.status,
    $event.durationMillis, toJsonString(event)], [PgCommandOk],
    "postgres insert flow event failed")
  PQclear(res)

proc queryEvents(ledger: PostgresLedger; sql, value: string): seq[FlowEvent] =
  let res = execParams(ledger.conn, sql, [value], [PgTuplesOk],
    "postgres select flow events failed")
  try:
    for i in 0 ..< int(PQntuples(res)):
      result.add(flowEventFromJsonString(columnString(res, i, 0)))
  finally:
    PQclear(res)

proc events*(ledger: PostgresLedger): seq[FlowEvent] =
  let res = execParams(ledger.conn,
    "SELECT json FROM flowlogbook_flow_events ORDER BY seq ASC",
    [], [PgTuplesOk], "postgres select all flow events failed")
  try:
    for i in 0 ..< int(PQntuples(res)):
      result.add(flowEventFromJsonString(columnString(res, i, 0)))
  finally:
    PQclear(res)

proc eventsForRun*(ledger: PostgresLedger; runId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE run_id = $1 ORDER BY seq ASC", runId)

proc eventsForFlow*(ledger: PostgresLedger; flowId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE flow_id = $1 ORDER BY seq ASC", flowId)

proc eventsForVariant*(ledger: PostgresLedger; variantId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE variant_id = $1 ORDER BY seq ASC", variantId)

proc eventsForNode*(ledger: PostgresLedger; nodeId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE node_id = $1 ORDER BY seq ASC", nodeId)

proc eventsForEdge*(ledger: PostgresLedger; edgeId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE edge_id = $1 ORDER BY seq ASC", edgeId)

proc eventsBySource*(ledger: PostgresLedger; source: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE source = $1 ORDER BY seq ASC", source)

proc eventsByKind*(ledger: PostgresLedger; kind: FlowEventKind): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE kind = $1 ORDER BY seq ASC", $kind)

proc eventsByStatus*(ledger: PostgresLedger; status: RunStatus): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flowlogbook_flow_events WHERE status = $1 ORDER BY seq ASC", $status)

proc decide*(ledger: PostgresLedger; input: RunInput;
    policy: ReusePolicy = defaultReusePolicy()): ResumeDecision =
  let fp = fingerprint(input)
  if not ledger.contains(fp):
    return executeDecision(fp, "no prior run record")
  let prior = ledger.get(fp)
  let reusable = canReuse(prior, policy)
  if reusable.ok:
    return reuseDecision(prior, policy)
  executeDecision(fp, reusable.reason, prior, hasRecord = true)
