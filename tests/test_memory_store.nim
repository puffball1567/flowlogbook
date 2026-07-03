import std/unittest

import flowlogbook

suite "memory ledger":
  test "missing record executes":
    let input = runInput(taskName = "task", command = "echo hi")
    let ledger = initMemoryLedger()
    let decision = ledger.decide(input)
    check decision.kind == rdkExecute
    check decision.reason == "no prior run record"

  test "completed record with present outputs reuses":
    let input = runInput(taskName = "task", command = "echo hi")
    var ledger = initMemoryLedger()
    ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")]))
    let decision = ledger.decide(input)
    check decision.kind == rdkReuse
    check decision.hasRecord
    check ledger.attempts(fingerprint(input)) == 1

  test "failed record executes":
    let input = runInput(taskName = "task", command = "echo hi")
    var ledger = initMemoryLedger()
    ledger.record(failedRecord(input, message = "tool failed"))
    let decision = ledger.decide(input)
    check decision.kind == rdkExecute
    check decision.hasRecord
    check decision.reason == "previous run is not completed"

  test "completed record without outputs executes":
    let input = runInput(taskName = "task", command = "echo hi")
    var ledger = initMemoryLedger()
    ledger.record(completedRecord(input, []))
    let decision = ledger.decide(input)
    check decision.kind == rdkExecute
    check decision.reason == "previous run has no recorded outputs"

  test "missing output executes":
    let input = runInput(taskName = "task", command = "echo hi")
    var ledger = initMemoryLedger()
    ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out", present = false)]))
    let decision = ledger.decide(input)
    check decision.kind == rdkExecute
    check decision.reason == "previous output is marked missing: out.txt"

  test "empty fingerprint record is rejected":
    var ledger = initMemoryLedger()
    expect ValueError:
      ledger.record(RunRecord())

  test "ledger keeps append-only history and decides from latest record":
    let input = runInput(taskName = "task", command = "echo hi")
    let fp = fingerprint(input)
    var ledger = initMemoryLedger()
    ledger.record(failedRecord(input, attempt = 1, message = "first failed"))
    ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")], attempt = 2))

    check ledger.attempts(fp) == 2
    check ledger.history(fp).len == 2
    check ledger.get(fp).status == rsCompleted
    check ledger.decide(input).kind == rdkReuse

  test "policy can allow completed records without outputs":
    let input = runInput(taskName = "side-effect", command = "notify")
    var ledger = initMemoryLedger()
    ledger.record(completedRecord(input, []))

    var policy = defaultReusePolicy()
    policy.requireOutputs = false

    let decision = ledger.decide(input, policy)
    check decision.kind == rdkReuse

  test "policy can require output digests":
    let input = runInput(taskName = "task", command = "echo hi")
    var ledger = initMemoryLedger()
    ledger.record(completedRecord(input, @[artifact("out.txt", "")]))

    var policy = defaultReusePolicy()
    policy.requireOutputDigests = true

    let decision = ledger.decide(input, policy)
    check decision.kind == rdkExecute
    check decision.reason == "previous output has no digest: out.txt"

  test "records node and edge events for external flow analysis":
    var ledger = initMemoryLedger()
    ledger.recordEvent(nodeEvent(
      id = "evt-1",
      source = "nextflow-trace",
      flowId = "pipeline",
      runId = "run-1",
      variantId = "A",
      nodeId = "align",
      kind = fekNodeFinished,
      status = rsCompleted,
      durationMillis = 1200,
      metrics = @[kv("records", "42")]
    ))
    ledger.recordEvent(edgeEvent(
      id = "evt-2",
      source = "nextflow-trace",
      flowId = "pipeline",
      runId = "run-1",
      variantId = "A",
      edgeId = "align->call",
      kind = fekEdgeSatisfied,
      status = rsCompleted,
      durationMillis = 300
    ))

    check ledger.events.len == 2
    check ledger.eventsForRun("run-1").len == 2
    check ledger.eventsForNode("align")[0].durationMillis == 1200
    check ledger.eventsForNode("align")[0].metrics[0].key == "records"
    check ledger.eventsForEdge("align->call")[0].kind == fekEdgeSatisfied
    check ledger.eventsForFlow("pipeline").len == 2
    check ledger.eventsForVariant("A").len == 2
    check ledger.eventsBySource("nextflow-trace").len == 2
    check ledger.eventsByKind(fekNodeFinished).len == 1
    check ledger.eventsByStatus(rsCompleted).len == 2

  test "invalid flow event is rejected":
    var ledger = initMemoryLedger()
    expect ValueError:
      ledger.recordEvent(flowEvent(
        id = "",
        source = "adapter",
        flowId = "flow",
        runId = "run",
        kind = fekNote
      ))

  test "note event helper does not require node or edge ids":
    var ledger = initMemoryLedger()
    ledger.recordEvent(noteEvent(
      id = "note-1",
      source = "adapter",
      flowId = "flow",
      runId = "run",
      message = "import completed"
    ))

    check ledger.events.len == 1
    check ledger.events[0].kind == fekNote
    check ledger.events[0].status == rsCompleted
    check ledger.events[0].message == "import completed"
