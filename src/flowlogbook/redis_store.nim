import std/net
import std/strutils

import ./decision
import ./fingerprint
import ./jsonio
import ./types
import ./validation

type
  RedisConfig* = object
    host*: string
    port*: Port
    password*: string
    database*: int
    keyPrefix*: string

  RedisLedger* = object
    socket: Socket
    keyPrefix: string

proc defaultRedisConfig*(): RedisConfig =
  RedisConfig(
    host: "127.0.0.1",
    port: Port(6379),
    password: "",
    database: 0,
    keyPrefix: "flowlogbook"
  )

proc sendCommand(socket: Socket; parts: openArray[string]) =
  var payload = "*" & $parts.len & "\c\L"
  for part in parts:
    payload.add("$" & $part.len & "\c\L")
    payload.add(part)
    payload.add("\c\L")
  socket.send(payload)

proc readLine(socket: Socket): string =
  result = ""
  while true:
    let ch = socket.recv(1)
    if ch.len == 0:
      raise newException(IOError, "redis connection closed")
    result.add(ch)
    if result.len >= 2 and result[^2] == '\c' and result[^1] == '\L':
      result.setLen(result.len - 2)
      return

proc readExact(socket: Socket; size: int): string =
  result = ""
  while result.len < size:
    let chunk = socket.recv(size - result.len)
    if chunk.len == 0:
      raise newException(IOError, "redis connection closed")
    result.add(chunk)

proc readBulk(socket: Socket; firstLine: string): string =
  let size = parseInt(firstLine[1 .. ^1])
  if size < 0:
    return ""
  result = readExact(socket, size)
  let endLine = readExact(socket, 2)
  if endLine != "\c\L":
    raise newException(ValueError, "invalid redis bulk string terminator")

proc readReply(socket: Socket): seq[string] =
  let first = readLine(socket)
  if first.len == 0:
    raise newException(ValueError, "empty redis reply")
  case first[0]
  of '+':
    return @[first[1 .. ^1]]
  of ':':
    return @[first[1 .. ^1]]
  of '-':
    raise newException(ValueError, "redis error: " & first[1 .. ^1])
  of '$':
    return @[readBulk(socket, first)]
  of '*':
    let count = parseInt(first[1 .. ^1])
    if count < 0:
      return @[]
    for _ in 0 ..< count:
      let item = readLine(socket)
      if item.len == 0:
        raise newException(ValueError, "empty redis array item")
      if item[0] != '$':
        raise newException(ValueError, "unsupported redis array item: " & item)
      result.add(readBulk(socket, item))
  else:
    raise newException(ValueError, "unsupported redis reply: " & first)

proc command(ledger: RedisLedger; parts: openArray[string]): seq[string] =
  sendCommand(ledger.socket, parts)
  readReply(ledger.socket)

proc commandInt(ledger: RedisLedger; parts: openArray[string]): int =
  let reply = command(ledger, parts)
  if reply.len != 1:
    raise newException(ValueError, "redis integer reply expected")
  parseInt(reply[0])

proc commandOk(ledger: RedisLedger; parts: openArray[string]) =
  let reply = command(ledger, parts)
  if reply.len != 1 or reply[0] != "OK":
    raise newException(ValueError, "redis OK reply expected")

proc key(ledger: RedisLedger; parts: varargs[string]): string =
  result = ledger.keyPrefix
  for part in parts:
    result.add(":")
    result.add(part)

proc openRedisLedger*(config: RedisConfig): RedisLedger =
  let socket = newSocket()
  socket.connect(config.host, config.port)
  result = RedisLedger(socket: socket, keyPrefix: config.keyPrefix)
  if config.password.len > 0:
    commandOk(result, ["AUTH", config.password])
  if config.database != 0:
    commandOk(result, ["SELECT", $config.database])

proc openRedisLedger*(host = "127.0.0.1"; port: Port = Port(6379);
    password = ""; database = 0; keyPrefix = "flowlogbook"): RedisLedger =
  openRedisLedger(RedisConfig(
    host: host,
    port: port,
    password: password,
    database: database,
    keyPrefix: keyPrefix
  ))

proc close*(ledger: var RedisLedger) =
  if not ledger.socket.isNil:
    ledger.socket.close()

proc record*(ledger: RedisLedger; record: RunRecord) =
  requireValid(record)
  discard commandInt(ledger, ["RPUSH", key(ledger, "run", record.fingerprint),
    toJsonString(record)])

proc contains*(ledger: RedisLedger; fingerprint: string): bool =
  commandInt(ledger, ["EXISTS", key(ledger, "run", fingerprint)]) > 0

proc history*(ledger: RedisLedger; fingerprint: string): seq[RunRecord] =
  for item in command(ledger, ["LRANGE", key(ledger, "run", fingerprint), "0", "-1"]):
    result.add(runRecordFromJsonString(item))

proc get*(ledger: RedisLedger; fingerprint: string): RunRecord =
  let reply = command(ledger, ["LINDEX", key(ledger, "run", fingerprint), "-1"])
  if reply.len == 0 or reply[0].len == 0:
    raise newException(KeyError, "run record not found: " & fingerprint)
  runRecordFromJsonString(reply[0])

proc attempts*(ledger: RedisLedger; fingerprint: string): int =
  commandInt(ledger, ["LLEN", key(ledger, "run", fingerprint)])

proc addEventIndex(ledger: RedisLedger; indexName, value, json: string) =
  discard commandInt(ledger, ["RPUSH", key(ledger, "event", indexName, value), json])

proc recordEvent*(ledger: RedisLedger; event: FlowEvent) =
  requireValid(event)
  let added = commandInt(ledger, ["SADD", key(ledger, "event_ids"), event.id])
  if added == 0:
    raise newException(ValueError, "duplicate flow event id: " & event.id)

  let json = toJsonString(event)
  discard commandInt(ledger, ["RPUSH", key(ledger, "events"), json])
  addEventIndex(ledger, "run", event.runId, json)
  addEventIndex(ledger, "flow", event.flowId, json)
  addEventIndex(ledger, "variant", event.variantId, json)
  addEventIndex(ledger, "node", event.nodeId, json)
  addEventIndex(ledger, "edge", event.edgeId, json)
  addEventIndex(ledger, "source", event.source, json)
  addEventIndex(ledger, "kind", $event.kind, json)
  addEventIndex(ledger, "status", $event.status, json)

proc readEvents(ledger: RedisLedger; keyName: string): seq[FlowEvent] =
  for item in command(ledger, ["LRANGE", keyName, "0", "-1"]):
    result.add(flowEventFromJsonString(item))

proc events*(ledger: RedisLedger): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "events"))

proc eventsForRun*(ledger: RedisLedger; runId: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "run", runId))

proc eventsForFlow*(ledger: RedisLedger; flowId: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "flow", flowId))

proc eventsForVariant*(ledger: RedisLedger; variantId: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "variant", variantId))

proc eventsForNode*(ledger: RedisLedger; nodeId: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "node", nodeId))

proc eventsForEdge*(ledger: RedisLedger; edgeId: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "edge", edgeId))

proc eventsBySource*(ledger: RedisLedger; source: string): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "source", source))

proc eventsByKind*(ledger: RedisLedger; kind: FlowEventKind): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "kind", $kind))

proc eventsByStatus*(ledger: RedisLedger; status: RunStatus): seq[FlowEvent] =
  readEvents(ledger, key(ledger, "event", "status", $status))

proc decide*(ledger: RedisLedger; input: RunInput;
    policy: ReusePolicy = defaultReusePolicy()): ResumeDecision =
  let fp = fingerprint(input)
  if not ledger.contains(fp):
    return executeDecision(fp, "no prior run record")
  let prior = ledger.get(fp)
  let reusable = canReuse(prior, policy)
  if reusable.ok:
    return reuseDecision(prior, policy)
  executeDecision(fp, reusable.reason, prior, hasRecord = true)
