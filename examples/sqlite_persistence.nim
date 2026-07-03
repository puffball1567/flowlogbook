import std/os

import flowlogbook
import flowlogbook/sqlite_store

let path = getTempDir() / "flowlogbook_example.sqlite3"
if fileExists(path):
  removeFile(path)

let input = runInput(
  taskName = "daily-report",
  command = "build-report --date 2026-07-03",
  params = @[kv("date", "2026-07-03")]
)

var ledger = openSqliteLedger(path)
ledger.record(completedRecord(input, @[artifact("report.html", "sha256:report")]))
ledger.close()

var reopened = openSqliteLedger(path)
let decision = reopened.decide(input)
doAssert decision.kind == rdkReuse
doAssert reopened.attempts(fingerprint(input)) == 1
reopened.close()

removeFile(path)
