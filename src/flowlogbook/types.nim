type
  KeyValue* = object
    key*: string
    value*: string

  Artifact* = object
    path*: string
    digest*: string
    present*: bool

  RunInput* = object
    taskName*: string
    command*: string
    inputs*: seq[Artifact]
    params*: seq[KeyValue]
    env*: seq[KeyValue]
    implementation*: string

  RunStatus* = enum
    rsPending,
    rsRunning,
    rsCompleted,
    rsFailed,
    rsSkipped

  FlowEventKind* = enum
    fekNodeStarted,
    fekNodeFinished,
    fekEdgeWaiting,
    fekEdgeSatisfied,
    fekEdgeBlocked,
    fekMetric,
    fekNote

  RunRecord* = object
    fingerprint*: string
    input*: RunInput
    outputs*: seq[Artifact]
    status*: RunStatus
    attempt*: Natural
    message*: string

  FlowEvent* = object
    id*: string
    source*: string
    flowId*: string
    runId*: string
    variantId*: string
    nodeId*: string
    edgeId*: string
    kind*: FlowEventKind
    status*: RunStatus
    startedAt*: string
    finishedAt*: string
    durationMillis*: Natural
    metrics*: seq[KeyValue]
    message*: string

  ReusePolicy* = object
    requireCompleted*: bool
    requireOutputs*: bool
    requirePresentOutputs*: bool
    requireOutputDigests*: bool

  ResumeDecisionKind* = enum
    rdkExecute,
    rdkReuse

  ResumeDecision* = object
    kind*: ResumeDecisionKind
    fingerprint*: string
    reason*: string
    record*: RunRecord
    hasRecord*: bool

proc kv*(key, value: string): KeyValue =
  KeyValue(key: key, value: value)

proc artifact*(path, digest: string; present = true): Artifact =
  Artifact(path: path, digest: digest, present: present)

proc flowEvent*(
    id, source, flowId, runId: string;
    kind: FlowEventKind;
    variantId = "";
    nodeId = "";
    edgeId = "";
    status = rsPending;
    startedAt = "";
    finishedAt = "";
    durationMillis: Natural = 0;
    metrics: openArray[KeyValue] = [];
    message = ""): FlowEvent =
  FlowEvent(
    id: id,
    source: source,
    flowId: flowId,
    runId: runId,
    variantId: variantId,
    nodeId: nodeId,
    edgeId: edgeId,
    kind: kind,
    status: status,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMillis: durationMillis,
    metrics: @metrics,
    message: message
  )

proc nodeEvent*(
    id, source, flowId, runId, nodeId: string;
    kind: FlowEventKind;
    variantId = "";
    status = rsPending;
    startedAt = "";
    finishedAt = "";
    durationMillis: Natural = 0;
    metrics: openArray[KeyValue] = [];
    message = ""): FlowEvent =
  flowEvent(
    id = id,
    source = source,
    flowId = flowId,
    runId = runId,
    variantId = variantId,
    nodeId = nodeId,
    kind = kind,
    status = status,
    startedAt = startedAt,
    finishedAt = finishedAt,
    durationMillis = durationMillis,
    metrics = metrics,
    message = message
  )

proc edgeEvent*(
    id, source, flowId, runId, edgeId: string;
    kind: FlowEventKind;
    variantId = "";
    status = rsPending;
    startedAt = "";
    finishedAt = "";
    durationMillis: Natural = 0;
    metrics: openArray[KeyValue] = [];
    message = ""): FlowEvent =
  flowEvent(
    id = id,
    source = source,
    flowId = flowId,
    runId = runId,
    variantId = variantId,
    edgeId = edgeId,
    kind = kind,
    status = status,
    startedAt = startedAt,
    finishedAt = finishedAt,
    durationMillis = durationMillis,
    metrics = metrics,
    message = message
  )

proc noteEvent*(
    id, source, flowId, runId: string;
    message: string;
    variantId = "";
    metrics: openArray[KeyValue] = []): FlowEvent =
  flowEvent(
    id = id,
    source = source,
    flowId = flowId,
    runId = runId,
    variantId = variantId,
    kind = fekNote,
    status = rsCompleted,
    metrics = metrics,
    message = message
  )

proc defaultReusePolicy*(): ReusePolicy =
  ReusePolicy(
    requireCompleted: true,
    requireOutputs: true,
    requirePresentOutputs: true,
    requireOutputDigests: false
  )

proc runInput*(
    taskName, command: string;
    inputs: openArray[Artifact] = [];
    params: openArray[KeyValue] = [];
    env: openArray[KeyValue] = [];
    implementation = ""): RunInput =
  RunInput(
    taskName: taskName,
    command: command,
    inputs: @inputs,
    params: @params,
    env: @env,
    implementation: implementation
  )
