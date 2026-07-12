import flowlogbook

proc main() =
  var totalEvents = 0
  var ledger = initMemoryLedger()
  for i in 0 ..< 1000:
    let input = runInput(
      "task-" & $i,
      "echo ok",
      inputs = [artifact("input-" & $i, "sha256:" & $i)],
      params = [kv("batch", $i)]
    )
    let record = RunRecord(
      fingerprint: fingerprint(input),
      input: input,
      outputs: @[artifact("output-" & $i, "sha256:out" & $i)],
      status: rsCompleted,
      attempt: 1,
      message: "ok"
    )
    ledger.record(record)
    discard ledger.decide(input, defaultReusePolicy())

    let event = nodeEvent(
      "event-" & $i, "leak-probe", "flow", "run", "node-" & $i,
      fekNodeFinished,
      status = rsCompleted,
      durationMillis = Natural(i),
      metrics = [kv("work_units", "1")]
    )
    ledger.recordEvent(event)
    totalEvents += ledger.eventsForRun("run").len

  doAssert totalEvents > 0

main()
