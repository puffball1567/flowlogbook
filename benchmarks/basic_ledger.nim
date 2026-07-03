import std/monotimes
import std/os
import std/strformat
import std/times

import flowlogbook
import flowlogbook/sqlite_store

const Iterations = 1_000

proc elapsedMs(started: MonoTime): float =
  let elapsed = getMonoTime() - started
  elapsed.inNanoseconds.float / 1_000_000.0

proc makeInput(index: int): RunInput =
  runInput(
    taskName = "bench-" & $index,
    command = "echo " & $index,
    inputs = @[artifact("input-" & $index & ".txt", "sha256:" & $index)]
  )

proc runMemoryBench() =
  var ledger = initMemoryLedger()
  let started = getMonoTime()
  for i in 0 ..< Iterations:
    let input = makeInput(i)
    ledger.record(completedRecord(input, @[artifact("out-" & $i & ".txt", "sha256:out")]))
    doAssert ledger.decide(input).kind == rdkReuse
  echo &"memory ledger: {Iterations} record+decide operations in {elapsedMs(started):.2f} ms"

proc runSqliteBench() =
  let path = getTempDir() / "flowlogbook_bench.sqlite3"
  if fileExists(path):
    removeFile(path)

  var ledger = openSqliteLedger(path)
  let started = getMonoTime()
  ledger.beginTransaction()
  for i in 0 ..< Iterations:
    let input = makeInput(i)
    ledger.record(completedRecord(input, @[artifact("out-" & $i & ".txt", "sha256:out")]))
    doAssert ledger.decide(input).kind == rdkReuse
  ledger.commitTransaction()
  let duration = elapsedMs(started)
  ledger.close()
  removeFile(path)
  echo &"sqlite ledger: {Iterations} record+decide operations in {duration:.2f} ms"

when isMainModule:
  runMemoryBench()
  runSqliteBench()
