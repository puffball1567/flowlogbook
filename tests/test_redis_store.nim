import std/os
import std/net
import std/strutils
import std/unittest

import flowlogbook
import flowlogbook/redis_store

suite "redis ledger":
  test "imports without requiring a Redis server":
    check defaultRedisConfig().host == "127.0.0.1"

  test "persists run records and flow events when live Redis is enabled":
    if getEnv("FLOWLOGBOOK_TEST_REDIS") != "1":
      echo "skip: set FLOWLOGBOOK_TEST_REDIS=1 to run live Redis adapter tests"
      check true
    else:
      var config = defaultRedisConfig()
      config.host = getEnv("FLOWLOGBOOK_REDIS_HOST", "127.0.0.1")
      config.port = Port(parseInt(getEnv("FLOWLOGBOOK_REDIS_PORT", "6379")))
      config.password = getEnv("FLOWLOGBOOK_REDIS_PASSWORD")
      config.database = parseInt(getEnv("FLOWLOGBOOK_REDIS_DB", "0"))
      config.keyPrefix = "flowlogbook:test:" & $getCurrentProcessId()

      var ledger = openRedisLedger(config)
      let input = runInput(taskName = "redis task", command = "echo redis")
      let fp = fingerprint(input)
      ledger.record(failedRecord(input, attempt = 1, message = "failed"))
      ledger.record(completedRecord(input, @[artifact("out.txt", "sha256:out")], attempt = 2))

      check ledger.contains(fp)
      check ledger.attempts(fp) == 2
      check ledger.history(fp).len == 2
      check ledger.get(fp).status == rsCompleted
      check ledger.decide(input).kind == rdkReuse

      let event = nodeEvent(
        id = "evt-redis",
        source = "adapter",
        flowId = "flow",
        runId = "run",
        nodeId = "node",
        kind = fekNodeFinished,
        status = rsCompleted,
        durationMillis = 12
      )
      ledger.recordEvent(event)
      check ledger.events.len == 1
      check ledger.eventsForRun("run").len == 1
      check ledger.eventsForNode("node")[0].durationMillis == 12
      expect ValueError:
        ledger.recordEvent(event)
      ledger.close()
