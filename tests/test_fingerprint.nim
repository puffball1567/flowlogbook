import std/unittest

import flowlogbook

suite "fingerprint":
  test "same input produces same fingerprint":
    let a = runInput(
      taskName = "task",
      command = "echo hi",
      params = @[kv("b", "2"), kv("a", "1")]
    )
    let b = runInput(
      taskName = "task",
      command = "echo hi",
      params = @[kv("a", "1"), kv("b", "2")]
    )
    check fingerprint(a) == fingerprint(b)

  test "changed parameter changes fingerprint":
    let a = runInput(taskName = "task", command = "echo hi", params = @[kv("x", "1")])
    let b = runInput(taskName = "task", command = "echo hi", params = @[kv("x", "2")])
    check fingerprint(a) != fingerprint(b)

  test "changed input digest changes fingerprint":
    let a = runInput(taskName = "task", command = "echo hi", inputs = @[artifact("in", "a")])
    let b = runInput(taskName = "task", command = "echo hi", inputs = @[artifact("in", "b")])
    check fingerprint(a) != fingerprint(b)
