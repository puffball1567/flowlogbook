import ./decision
import ./fingerprint
import ./jsonio
import ./types
import ./validation

type
  Sqlite3 {.importc: "sqlite3", header: "sqlite3.h", incompleteStruct.} = object
  Sqlite3Stmt {.importc: "sqlite3_stmt", header: "sqlite3.h", incompleteStruct.} = object
  SqliteDestructor = proc(value: pointer) {.cdecl.}

  SqliteLedger* = object
    db: ptr Sqlite3

const
  SqliteOk = 0.cint
  SqliteRow = 100.cint
  SqliteDone = 101.cint
  SqliteTransient = cast[SqliteDestructor](-1)
  SqliteDynlib =
    when defined(windows):
      "sqlite3.dll"
    elif defined(macosx):
      "libsqlite3.dylib"
    else:
      "libsqlite3.so"
  SchemaVersion* = 1

proc sqlite3_open(filename: cstring; db: ptr ptr Sqlite3): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_close(db: ptr Sqlite3): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_errmsg(db: ptr Sqlite3): cstring
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_exec(db: ptr Sqlite3; sql: cstring; callback: pointer;
    firstArg: pointer; errmsg: ptr cstring): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_free(value: pointer)
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_prepare_v2(db: ptr Sqlite3; sql: cstring; nByte: cint;
    stmt: ptr ptr Sqlite3Stmt; tail: ptr cstring): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_finalize(stmt: ptr Sqlite3Stmt): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_step(stmt: ptr Sqlite3Stmt): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_bind_text(stmt: ptr Sqlite3Stmt; index: cint; value: cstring;
    n: cint; destructor: SqliteDestructor): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_bind_int64(stmt: ptr Sqlite3Stmt; index: cint; value: clonglong): cint
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_column_text(stmt: ptr Sqlite3Stmt; index: cint): cstring
    {.importc, cdecl, dynlib: SqliteDynlib.}
proc sqlite3_column_int64(stmt: ptr Sqlite3Stmt; index: cint): clonglong
    {.importc, cdecl, dynlib: SqliteDynlib.}

proc sqliteError(db: ptr Sqlite3; prefix: string): ref ValueError =
  newException(ValueError, prefix & ": " & $sqlite3_errmsg(db))

proc checkOk(db: ptr Sqlite3; code: cint; prefix: string) =
  if code != SqliteOk:
    raise sqliteError(db, prefix)

proc checkBind(db: ptr Sqlite3; code: cint; prefix: string) =
  if code != SqliteOk:
    raise sqliteError(db, prefix)

proc execSql(db: ptr Sqlite3; sql: string) =
  var err: cstring
  let code = sqlite3_exec(db, sql.cstring, nil, nil, addr err)
  if code != SqliteOk:
    let message =
      if err.isNil:
        $sqlite3_errmsg(db)
      else:
        let text = $err
        sqlite3_free(err)
        text
    raise newException(ValueError, "sqlite exec failed: " & message)

proc prepare(db: ptr Sqlite3; sql: string): ptr Sqlite3Stmt =
  var stmt: ptr Sqlite3Stmt
  checkOk(db, sqlite3_prepare_v2(db, sql.cstring, -1, addr stmt, nil),
    "sqlite prepare failed")
  stmt

proc bindText(db: ptr Sqlite3; stmt: ptr Sqlite3Stmt; index: cint; value: string) =
  checkBind(db, sqlite3_bind_text(stmt, index, value.cstring, -1, SqliteTransient),
    "sqlite bind text failed")

proc bindInt(db: ptr Sqlite3; stmt: ptr Sqlite3Stmt; index: cint; value: Natural) =
  checkBind(db, sqlite3_bind_int64(stmt, index, clonglong(value)),
    "sqlite bind int failed")

proc columnString(stmt: ptr Sqlite3Stmt; index: cint): string =
  let value = sqlite3_column_text(stmt, index)
  if value.isNil:
    return ""
  $value

proc initSchema(db: ptr Sqlite3) =
  execSql(db, """
CREATE TABLE IF NOT EXISTS flowlogbook_schema (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL
);
INSERT OR IGNORE INTO flowlogbook_schema (id, version) VALUES (1, 1);
CREATE TABLE IF NOT EXISTS run_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_run_records_fingerprint_id
  ON run_records(fingerprint, id);
CREATE TABLE IF NOT EXISTS flow_events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL,
  flow_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  variant_id TEXT NOT NULL,
  node_id TEXT NOT NULL,
  edge_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  duration_millis INTEGER NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flow_events_flow_id
  ON flow_events(flow_id);
CREATE INDEX IF NOT EXISTS idx_flow_events_run_id
  ON flow_events(run_id);
CREATE INDEX IF NOT EXISTS idx_flow_events_variant_id
  ON flow_events(variant_id);
CREATE INDEX IF NOT EXISTS idx_flow_events_node_id
  ON flow_events(node_id);
CREATE INDEX IF NOT EXISTS idx_flow_events_edge_id
  ON flow_events(edge_id);
CREATE INDEX IF NOT EXISTS idx_flow_events_source
  ON flow_events(source);
CREATE INDEX IF NOT EXISTS idx_flow_events_kind
  ON flow_events(kind);
CREATE INDEX IF NOT EXISTS idx_flow_events_status
  ON flow_events(status);
""")

proc schemaVersion*(ledger: SqliteLedger): int =
  let stmt = prepare(ledger.db,
    "SELECT version FROM flowlogbook_schema WHERE id = 1")
  try:
    let code = sqlite3_step(stmt)
    if code == SqliteRow:
      return int(sqlite3_column_int64(stmt, 0))
    if code == SqliteDone:
      raise newException(ValueError, "sqlite schema version is missing")
    raise sqliteError(ledger.db, "sqlite select schema version failed")
  finally:
    discard sqlite3_finalize(stmt)

proc openSqliteLedger*(path: string): SqliteLedger =
  var db: ptr Sqlite3
  if sqlite3_open(path.cstring, addr db) != SqliteOk:
    let message =
      if db.isNil:
        "unable to allocate sqlite connection"
      else:
        $sqlite3_errmsg(db)
    if not db.isNil:
      discard sqlite3_close(db)
    raise newException(ValueError, "sqlite open failed: " & message)
  try:
    initSchema(db)
  except:
    discard sqlite3_close(db)
    raise
  SqliteLedger(db: db)

proc close*(ledger: var SqliteLedger) =
  if not ledger.db.isNil:
    checkOk(ledger.db, sqlite3_close(ledger.db), "sqlite close failed")
    ledger.db = nil

proc beginTransaction*(ledger: SqliteLedger) =
  execSql(ledger.db, "BEGIN")

proc commitTransaction*(ledger: SqliteLedger) =
  execSql(ledger.db, "COMMIT")

proc rollbackTransaction*(ledger: SqliteLedger) =
  execSql(ledger.db, "ROLLBACK")

proc record*(ledger: SqliteLedger; record: RunRecord) =
  requireValid(record)
  let stmt = prepare(ledger.db,
    "INSERT INTO run_records (fingerprint, status, attempt, json) VALUES (?, ?, ?, ?)")
  try:
    bindText(ledger.db, stmt, 1, record.fingerprint)
    bindText(ledger.db, stmt, 2, $record.status)
    bindInt(ledger.db, stmt, 3, record.attempt)
    bindText(ledger.db, stmt, 4, toJsonString(record))
    let code = sqlite3_step(stmt)
    if code != SqliteDone:
      raise sqliteError(ledger.db, "sqlite insert run record failed")
  finally:
    discard sqlite3_finalize(stmt)

proc contains*(ledger: SqliteLedger; fingerprint: string): bool =
  let stmt = prepare(ledger.db,
    "SELECT 1 FROM run_records WHERE fingerprint = ? LIMIT 1")
  try:
    bindText(ledger.db, stmt, 1, fingerprint)
    sqlite3_step(stmt) == SqliteRow
  finally:
    discard sqlite3_finalize(stmt)

proc history*(ledger: SqliteLedger; fingerprint: string): seq[RunRecord] =
  let stmt = prepare(ledger.db,
    "SELECT json FROM run_records WHERE fingerprint = ? ORDER BY id ASC")
  try:
    bindText(ledger.db, stmt, 1, fingerprint)
    while true:
      let code = sqlite3_step(stmt)
      if code == SqliteRow:
        result.add(runRecordFromJsonString(columnString(stmt, 0)))
      elif code == SqliteDone:
        break
      else:
        raise sqliteError(ledger.db, "sqlite select run history failed")
  finally:
    discard sqlite3_finalize(stmt)

proc get*(ledger: SqliteLedger; fingerprint: string): RunRecord =
  let stmt = prepare(ledger.db,
    "SELECT json FROM run_records WHERE fingerprint = ? ORDER BY id DESC LIMIT 1")
  try:
    bindText(ledger.db, stmt, 1, fingerprint)
    let code = sqlite3_step(stmt)
    if code == SqliteRow:
      return runRecordFromJsonString(columnString(stmt, 0))
    if code == SqliteDone:
      raise newException(KeyError, "run record not found: " & fingerprint)
    raise sqliteError(ledger.db, "sqlite select latest run record failed")
  finally:
    discard sqlite3_finalize(stmt)

proc attempts*(ledger: SqliteLedger; fingerprint: string): int =
  let stmt = prepare(ledger.db,
    "SELECT COUNT(*) FROM run_records WHERE fingerprint = ?")
  try:
    bindText(ledger.db, stmt, 1, fingerprint)
    let code = sqlite3_step(stmt)
    if code != SqliteRow:
      raise sqliteError(ledger.db, "sqlite count attempts failed")
    int(sqlite3_column_int64(stmt, 0))
  finally:
    discard sqlite3_finalize(stmt)

proc recordEvent*(ledger: SqliteLedger; event: FlowEvent) =
  requireValid(event)
  let stmt = prepare(ledger.db, """
INSERT INTO flow_events (
  id, source, flow_id, run_id, variant_id, node_id, edge_id, kind, status,
  duration_millis, json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
""")
  try:
    bindText(ledger.db, stmt, 1, event.id)
    bindText(ledger.db, stmt, 2, event.source)
    bindText(ledger.db, stmt, 3, event.flowId)
    bindText(ledger.db, stmt, 4, event.runId)
    bindText(ledger.db, stmt, 5, event.variantId)
    bindText(ledger.db, stmt, 6, event.nodeId)
    bindText(ledger.db, stmt, 7, event.edgeId)
    bindText(ledger.db, stmt, 8, $event.kind)
    bindText(ledger.db, stmt, 9, $event.status)
    bindInt(ledger.db, stmt, 10, event.durationMillis)
    bindText(ledger.db, stmt, 11, toJsonString(event))
    let code = sqlite3_step(stmt)
    if code != SqliteDone:
      raise sqliteError(ledger.db, "sqlite insert flow event failed")
  finally:
    discard sqlite3_finalize(stmt)

proc queryEvents(ledger: SqliteLedger; sql, value: string): seq[FlowEvent] =
  let stmt = prepare(ledger.db, sql)
  try:
    bindText(ledger.db, stmt, 1, value)
    while true:
      let code = sqlite3_step(stmt)
      if code == SqliteRow:
        result.add(flowEventFromJsonString(columnString(stmt, 0)))
      elif code == SqliteDone:
        break
      else:
        raise sqliteError(ledger.db, "sqlite select flow events failed")
  finally:
    discard sqlite3_finalize(stmt)

proc events*(ledger: SqliteLedger): seq[FlowEvent] =
  let stmt = prepare(ledger.db, "SELECT json FROM flow_events ORDER BY seq ASC")
  try:
    while true:
      let code = sqlite3_step(stmt)
      if code == SqliteRow:
        result.add(flowEventFromJsonString(columnString(stmt, 0)))
      elif code == SqliteDone:
        break
      else:
        raise sqliteError(ledger.db, "sqlite select all flow events failed")
  finally:
    discard sqlite3_finalize(stmt)

proc eventsForRun*(ledger: SqliteLedger; runId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE run_id = ? ORDER BY seq ASC", runId)

proc eventsForFlow*(ledger: SqliteLedger; flowId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE flow_id = ? ORDER BY seq ASC", flowId)

proc eventsForVariant*(ledger: SqliteLedger; variantId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE variant_id = ? ORDER BY seq ASC", variantId)

proc eventsForNode*(ledger: SqliteLedger; nodeId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE node_id = ? ORDER BY seq ASC", nodeId)

proc eventsForEdge*(ledger: SqliteLedger; edgeId: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE edge_id = ? ORDER BY seq ASC", edgeId)

proc eventsBySource*(ledger: SqliteLedger; source: string): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE source = ? ORDER BY seq ASC", source)

proc eventsByKind*(ledger: SqliteLedger; kind: FlowEventKind): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE kind = ? ORDER BY seq ASC", $kind)

proc eventsByStatus*(ledger: SqliteLedger; status: RunStatus): seq[FlowEvent] =
  queryEvents(ledger, "SELECT json FROM flow_events WHERE status = ? ORDER BY seq ASC", $status)

proc decide*(ledger: SqliteLedger; input: RunInput;
    policy: ReusePolicy = defaultReusePolicy()): ResumeDecision =
  let fp = fingerprint(input)
  if not ledger.contains(fp):
    return executeDecision(fp, "no prior run record")

  let prior = ledger.get(fp)
  let reusable = canReuse(prior, policy)
  if reusable.ok:
    return reuseDecision(prior, policy)

  executeDecision(fp, reusable.reason, prior, hasRecord = true)
