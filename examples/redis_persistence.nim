import flowlogbook
import flowlogbook/redis_store

proc main() =
  let input = runInput(
    taskName = "redis-example",
    command = "echo redis",
    inputs = @[artifact("input.txt", "sha256:input")]
  )

  var ledger = openRedisLedger(host = "127.0.0.1", keyPrefix = "flowlogbook:example")
  defer:
    ledger.close()

  ledger.record(completedRecord(input, @[artifact("output.txt", "sha256:output")]))

  let decision = ledger.decide(input)
  doAssert decision.kind == rdkReuse

when isMainModule:
  main()
