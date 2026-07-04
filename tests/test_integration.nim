import std/strutils
import std/unittest

import flowlogbook

suite "integration":
  test "validates batches for FlowCaptain-style adapters":
    let input = runInput("task", "echo ok")
    let record = completedRecord(input, outputs = @[artifact("out.txt", "abc")])
    let event = nodeEvent(
      "e1", "adapter", "flow", "run-1", "node-1",
      fekNodeFinished,
      status = rsCompleted,
      durationMillis = 10
    )

    let outcome = validate(initLogbookInput(records = [record], events = [event]))

    check outcome.ok
    check outcome.acceptedRecords == 1
    check outcome.acceptedEvents == 1
    check outcome.errors.len == 0

  test "returns validation errors as data":
    let badRecord = RunRecord()
    let badEvent = FlowEvent()

    let outcome = validate(initLogbookInput(records = [badRecord], events = [badEvent]))

    check not outcome.ok
    check outcome.acceptedRecords == 0
    check outcome.acceptedEvents == 0
    check outcome.errors.len == 2
    check outcome.errors[0].startsWith("record[0]:")
    check outcome.errors[1].startsWith("event[0]:")
