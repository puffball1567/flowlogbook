import std/os
import std/unittest

import flowlogbook
import flowlogbook/sqlite_store

proc sqliteTestPath(name: string): string =
  getTempDir() / ("flowlogbook_" & name & ".sqlite3")

suite "sqlite ledger":
  test "persists run records and decides from latest record":
    let path = sqliteTestPath("records")
    if fileExists(path):
      removeFile(path)

    let input = runInput(taskName = "task", command = "echo hi")
    let fp = fingerprint(input)

    var ledger = openSqliteLedger(path)
    check ledger.schemaVersion == sqlite_store.SchemaVersion
    ledger.record(failedRecord(input, attempt = 1, message = "failed"))
    ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")], attempt = 2))

    check ledger.contains(fp)
    check ledger.attempts(fp) == 2
    check ledger.history(fp).len == 2
    check ledger.get(fp).status == rsCompleted
    check ledger.decide(input).kind == rdkReuse
    ledger.close()

    var reopened = openSqliteLedger(path)
    check reopened.schemaVersion == sqlite_store.SchemaVersion
    check reopened.attempts(fp) == 2
    check reopened.get(fp).outputs[0].path == "out.txt"
    reopened.close()

    removeFile(path)

  test "persists flow events and supports search helpers":
    let path = sqliteTestPath("events")
    if fileExists(path):
      removeFile(path)

    var ledger = openSqliteLedger(path)
    ledger.recordEvent(nodeEvent(
      id = "evt-1",
      source = "adapter",
      flowId = "flow",
      runId = "run",
      variantId = "A",
      nodeId = "node-a",
      kind = fekNodeFinished,
      status = rsCompleted,
      durationMillis = 100
    ))
    ledger.recordEvent(edgeEvent(
      id = "evt-2",
      source = "adapter",
      flowId = "flow",
      runId = "run",
      variantId = "A",
      edgeId = "node-a->node-b",
      kind = fekEdgeSatisfied,
      status = rsCompleted,
      durationMillis = 20
    ))

    check ledger.events.len == 2
    check ledger.eventsForRun("run").len == 2
    check ledger.eventsForFlow("flow").len == 2
    check ledger.eventsForVariant("A").len == 2
    check ledger.eventsForNode("node-a")[0].durationMillis == 100
    check ledger.eventsForEdge("node-a->node-b")[0].kind == fekEdgeSatisfied
    check ledger.eventsBySource("adapter").len == 2
    check ledger.eventsByKind(fekNodeFinished).len == 1
    check ledger.eventsByStatus(rsCompleted).len == 2
    ledger.close()

    removeFile(path)

  test "rejects invalid records and duplicate event ids":
    let path = sqliteTestPath("invalid")
    if fileExists(path):
      removeFile(path)

    var ledger = openSqliteLedger(path)
    expect ValueError:
      ledger.record(RunRecord())

    let event = noteEvent(
      id = "dup",
      source = "adapter",
      flowId = "flow",
      runId = "run",
      message = "first"
    )
    ledger.recordEvent(event)
    expect ValueError:
      ledger.recordEvent(event)

    ledger.close()
    removeFile(path)

  test "transaction rollback discards uncommitted records":
    let path = sqliteTestPath("transaction")
    if fileExists(path):
      removeFile(path)

    let input = runInput(taskName = "txn", command = "echo txn")
    let fp = fingerprint(input)

    var ledger = openSqliteLedger(path)
    ledger.beginTransaction()
    ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")]))
    ledger.rollbackTransaction()

    check not ledger.contains(fp)
    ledger.close()
    removeFile(path)
