import flowlogbook
import flowlogbook/postgres_store

proc main() =
  let input = runInput(
    taskName = "postgres-example",
    command = "echo postgres",
    inputs = @[artifact("input.txt", "sha256:input")]
  )

  var ledger = openPostgresLedger("host=127.0.0.1 dbname=flowlogbook user=flowlogbook")
  defer:
    ledger.close()

  ledger.record(completedRecord(input, @[artifact("output.txt", "sha256:output")]))

  let decision = ledger.decide(input)
  doAssert decision.kind == rdkReuse

when isMainModule:
  main()
