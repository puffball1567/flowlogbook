import std/json
import std/unittest

import flowlogbook

suite "json io":
  test "run record round trips through json string":
    let input = runInput(
      taskName = "task",
      command = "echo hi",
      inputs = @[artifact("in.txt", "sha256:in")],
      params = @[kv("mode", "fast")],
      env = @[kv("ENV", "test")],
      implementation = "v1"
    )
    let record = completedRecord(
      input,
      @[artifact("out.txt", "sha256:out")],
      attempt = 2,
      message = "done"
    )

    let decoded = runRecordFromJsonString(toJsonString(record))
    check decoded.fingerprint == record.fingerprint
    check decoded.input.taskName == "task"
    check decoded.input.params[0].key == "mode"
    check decoded.outputs[0].digest == "sha256:out"
    check decoded.status == rsCompleted
    check decoded.attempt == 2
    check decoded.message == "done"

  test "flow event round trips through json string":
    let event = edgeEvent(
      id = "evt-1",
      source = "adapter",
      flowId = "flow",
      runId = "run",
      variantId = "B",
      edgeId = "a->b",
      kind = fekEdgeSatisfied,
      status = rsCompleted,
      durationMillis = 123,
      metrics = @[kv("items", "10")],
      message = "ok"
    )

    let decoded = flowEventFromJsonString(toJsonString(event))
    check decoded.id == event.id
    check decoded.variantId == "B"
    check decoded.edgeId == "a->b"
    check decoded.kind == fekEdgeSatisfied
    check decoded.status == rsCompleted
    check decoded.durationMillis == 123
    check decoded.metrics[0].value == "10"

  test "unknown enum values are rejected":
    expect ValueError:
      discard runStatusFromString("completed")
    expect ValueError:
      discard flowEventKindFromString("edge")

  test "negative natural fields are rejected":
    let node = %*{
      "fingerprint": "fp",
      "input": {
        "taskName": "task",
        "command": "echo hi",
        "inputs": [],
        "params": [],
        "env": [],
        "implementation": ""
      },
      "outputs": [],
      "status": "rsCompleted",
      "attempt": -1,
      "message": ""
    }
    expect ValueError:
      discard runRecordFromJson(node)

  test "array fields reject wrong json types":
    expect ValueError:
      discard runInputFromJson(%*{
        "taskName": "task",
        "command": "echo hi",
        "inputs": {},
        "params": [],
        "env": [],
        "implementation": ""
      })
    expect ValueError:
      discard flowEventFromJson(%*{
        "id": "evt",
        "source": "adapter",
        "flowId": "flow",
        "runId": "run",
        "kind": "fekMetric",
        "status": "rsCompleted",
        "metrics": {}
      })
