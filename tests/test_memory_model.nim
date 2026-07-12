import std/unittest
import flowlogbook

suite "memory model":
  test "uses Nim ARC memory manager":
    when defined(gcArc):
      check true
    else:
      check false

  test "creates and releases event records under ARC":
    var totalMetrics = 0
    for i in 0 ..< 200:
      let input = runInput(
        "task-" & $i,
        "echo ok",
        inputs = [artifact("input-" & $i, "sha256:" & $i)],
        params = [kv("batch", $i)]
      )
      let event = nodeEvent(
        "event-" & $i, "memory-test", "flow", "run", "node-" & $i,
        fekNodeFinished,
        status = rsCompleted,
        durationMillis = Natural(i),
        metrics = [kv("work_units", "1")]
      )
      check input.inputs.len == 1
      totalMetrics += event.metrics.len
    check totalMetrics == 200
