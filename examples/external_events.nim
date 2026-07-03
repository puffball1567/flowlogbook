import flowlogbook

var ledger = initMemoryLedger()

ledger.recordEvent(nodeEvent(
  id = "evt-node-1",
  source = "external-workflow",
  flowId = "pipeline",
  runId = "run-2026-07-03",
  variantId = "A",
  nodeId = "align",
  kind = fekNodeFinished,
  status = rsCompleted,
  durationMillis = 1200,
  metrics = @[kv("records", "42")]
))

ledger.recordEvent(edgeEvent(
  id = "evt-edge-1",
  source = "external-workflow",
  flowId = "pipeline",
  runId = "run-2026-07-03",
  variantId = "A",
  edgeId = "align->call",
  kind = fekEdgeSatisfied,
  status = rsCompleted,
  durationMillis = 300
))

doAssert ledger.eventsForNode("align").len == 1
doAssert ledger.eventsForEdge("align->call").len == 1
doAssert ledger.eventsForFlow("pipeline").len == 2
