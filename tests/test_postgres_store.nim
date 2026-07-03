import std/os
import std/unittest

import flowlogbook
import flowlogbook/postgres_store

suite "postgres ledger":
  test "imports without opening libpq connections":
    check true

  test "persists run records and flow events when live PostgreSQL is enabled":
    if getEnv("FLOWLOGBOOK_TEST_POSTGRES") != "1":
      echo "skip: set FLOWLOGBOOK_TEST_POSTGRES=1 and FLOWLOGBOOK_POSTGRES_CONNINFO to run live PostgreSQL adapter tests"
      check true
    else:
      let conninfo = getEnv("FLOWLOGBOOK_POSTGRES_CONNINFO")
      check conninfo.len > 0

      var ledger = openPostgresLedger(conninfo)
      check ledger.schemaVersion == postgres_store.SchemaVersion
      ledger.beginTransaction()
      let input = runInput(taskName = "postgres task", command = "echo postgres")
      let fp = fingerprint(input)
      ledger.record(failedRecord(input, attempt = 1, message = "failed"))
      ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")], attempt = 2))
      ledger.commitTransaction()

      check ledger.contains(fp)
      check ledger.attempts(fp) >= 2
      check ledger.history(fp).len >= 2
      check ledger.get(fp).status == rsCompleted
      check ledger.decide(input).kind == rdkReuse

      let eventId = "evt-postgres-" & $getCurrentProcessId()
      let event = edgeEvent(
        id = eventId,
        source = "adapter",
        flowId = "flow",
        runId = "run",
        edgeId = "a->b",
        kind = fekEdgeSatisfied,
        status = rsCompleted,
        durationMillis = 15
      )
      ledger.recordEvent(event)
      check ledger.eventsForEdge("a->b").len >= 1
      expect ValueError:
        ledger.recordEvent(event)
      ledger.close()
