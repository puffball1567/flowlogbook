import std/json

import ./types

proc runStatusFromString*(value: string): RunStatus =
  case value
  of "rsPending": rsPending
  of "rsRunning": rsRunning
  of "rsCompleted": rsCompleted
  of "rsFailed": rsFailed
  of "rsSkipped": rsSkipped
  else:
    raise newException(ValueError, "unknown RunStatus: " & value)

proc flowEventKindFromString*(value: string): FlowEventKind =
  case value
  of "fekNodeStarted": fekNodeStarted
  of "fekNodeFinished": fekNodeFinished
  of "fekEdgeWaiting": fekEdgeWaiting
  of "fekEdgeSatisfied": fekEdgeSatisfied
  of "fekEdgeBlocked": fekEdgeBlocked
  of "fekMetric": fekMetric
  of "fekNote": fekNote
  else:
    raise newException(ValueError, "unknown FlowEventKind: " & value)

proc getStringField(node: JsonNode; key: string; default = ""): string =
  if node.hasKey(key):
    return node[key].getStr()
  default

proc getBoolField(node: JsonNode; key: string; default = false): bool =
  if node.hasKey(key):
    return node[key].getBool()
  default

proc getNaturalField(node: JsonNode; key: string; default = 0): Natural =
  var value = default
  if node.hasKey(key):
    value = node[key].getInt()
  if value < 0:
    raise newException(ValueError, key & " must not be negative")
  Natural(value)

proc getArrayField(node: JsonNode; key: string): seq[JsonNode] =
  if not node.hasKey(key):
    return @[]
  if node[key].kind != JArray:
    raise newException(ValueError, key & " must be an array")
  node[key].getElems()

proc toJson*(value: KeyValue): JsonNode =
  %*{
    "key": value.key,
    "value": value.value
  }

proc keyValueFromJson*(node: JsonNode): KeyValue =
  kv(
    key = node.getStringField("key"),
    value = node.getStringField("value")
  )

proc toJson*(value: Artifact): JsonNode =
  %*{
    "path": value.path,
    "digest": value.digest,
    "present": value.present
  }

proc artifactFromJson*(node: JsonNode): Artifact =
  artifact(
    path = node.getStringField("path"),
    digest = node.getStringField("digest"),
    present = node.getBoolField("present", true)
  )

proc toJson*(value: RunInput): JsonNode =
  result = newJObject()
  result["taskName"] = %value.taskName
  result["command"] = %value.command
  result["implementation"] = %value.implementation

  result["inputs"] = newJArray()
  for item in value.inputs:
    result["inputs"].add(toJson(item))

  result["params"] = newJArray()
  for item in value.params:
    result["params"].add(toJson(item))

  result["env"] = newJArray()
  for item in value.env:
    result["env"].add(toJson(item))

proc runInputFromJson*(node: JsonNode): RunInput =
  var inputs: seq[Artifact]
  for item in node.getArrayField("inputs"):
    inputs.add(artifactFromJson(item))

  var params: seq[KeyValue]
  for item in node.getArrayField("params"):
    params.add(keyValueFromJson(item))

  var env: seq[KeyValue]
  for item in node.getArrayField("env"):
    env.add(keyValueFromJson(item))

  runInput(
    taskName = node.getStringField("taskName"),
    command = node.getStringField("command"),
    inputs = inputs,
    params = params,
    env = env,
    implementation = node.getStringField("implementation")
  )

proc toJson*(value: RunRecord): JsonNode =
  result = newJObject()
  result["fingerprint"] = %value.fingerprint
  result["input"] = toJson(value.input)
  result["outputs"] = newJArray()
  for item in value.outputs:
    result["outputs"].add(toJson(item))
  result["status"] = %($value.status)
  result["attempt"] = %int(value.attempt)
  result["message"] = %value.message

proc runRecordFromJson*(node: JsonNode): RunRecord =
  var outputs: seq[Artifact]
  for item in node.getArrayField("outputs"):
    outputs.add(artifactFromJson(item))

  RunRecord(
    fingerprint: node.getStringField("fingerprint"),
    input: runInputFromJson(node["input"]),
    outputs: outputs,
    status: runStatusFromString(node.getStringField("status")),
    attempt: node.getNaturalField("attempt", 0),
    message: node.getStringField("message")
  )

proc toJson*(value: FlowEvent): JsonNode =
  result = newJObject()
  result["id"] = %value.id
  result["source"] = %value.source
  result["flowId"] = %value.flowId
  result["runId"] = %value.runId
  result["variantId"] = %value.variantId
  result["nodeId"] = %value.nodeId
  result["edgeId"] = %value.edgeId
  result["kind"] = %($value.kind)
  result["status"] = %($value.status)
  result["startedAt"] = %value.startedAt
  result["finishedAt"] = %value.finishedAt
  result["durationMillis"] = %int(value.durationMillis)
  result["metrics"] = newJArray()
  for item in value.metrics:
    result["metrics"].add(toJson(item))
  result["message"] = %value.message

proc flowEventFromJson*(node: JsonNode): FlowEvent =
  var metrics: seq[KeyValue]
  for item in node.getArrayField("metrics"):
    metrics.add(keyValueFromJson(item))

  flowEvent(
    id = node.getStringField("id"),
    source = node.getStringField("source"),
    flowId = node.getStringField("flowId"),
    runId = node.getStringField("runId"),
    variantId = node.getStringField("variantId"),
    nodeId = node.getStringField("nodeId"),
    edgeId = node.getStringField("edgeId"),
    kind = flowEventKindFromString(node.getStringField("kind")),
    status = runStatusFromString(node.getStringField("status", "rsPending")),
    startedAt = node.getStringField("startedAt"),
    finishedAt = node.getStringField("finishedAt"),
    durationMillis = node.getNaturalField("durationMillis", 0),
    metrics = metrics,
    message = node.getStringField("message")
  )

proc toJsonString*(value: RunInput): string =
  $toJson(value)

proc toJsonString*(value: RunRecord): string =
  $toJson(value)

proc toJsonString*(value: FlowEvent): string =
  $toJson(value)

proc runInputFromJsonString*(text: string): RunInput =
  runInputFromJson(parseJson(text))

proc runRecordFromJsonString*(text: string): RunRecord =
  runRecordFromJson(parseJson(text))

proc flowEventFromJsonString*(text: string): FlowEvent =
  flowEventFromJson(parseJson(text))
