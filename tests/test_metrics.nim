import std/math
import unittest

import flowlogbook

suite "metrics":
  test "summarizes event completeness":
    let events = @[
      nodeEvent("n1-start", "test", "flow", "run", "extract",
        fekNodeStarted, status = rsRunning),
      nodeEvent("n1-finish", "test", "flow", "run", "extract",
        fekNodeFinished, status = rsCompleted, durationMillis = 10,
        metrics = [kv("rows", "100")]),
      edgeEvent("e1", "test", "flow", "run", "extract-transform",
        fekEdgeWaiting, status = rsCompleted, durationMillis = 3),
      flowEvent("m1", "test", "flow", "run", fekMetric,
        status = rsCompleted, metrics = [kv("cpu", "0.8"), kv("mem", "128")])
    ]

    let metrics = events.eventMetrics()
    check metrics.eventCount == 4
    check metrics.nodeEventCount == 2
    check metrics.edgeEventCount == 1
    check metrics.metricEventCount == 1
    check metrics.metricValueCount == 3
    check metrics.completedCount == 3
    check metrics.totalDurationMillis == 13
    check metrics.eventsWithTiming == 2
    check metrics.eventsWithMetrics == 2
    check metrics.metricDensity == 0.75
    check metrics.timingCoverage == 50.0


  test "summarizes operational flow indicators":
    let events = @[
      nodeEvent("extract-finish", "test", "flow", "run", "extract",
        fekNodeFinished, status = rsCompleted, durationMillis = 1000,
        metrics = [kv("records", "100"), kv("accepted", "98"), kv("defects", "2")]),
      nodeEvent("transform-finish", "test", "flow", "run", "transform",
        fekNodeFinished, status = rsFailed, durationMillis = 3000,
        metrics = [kv("retry_count", "2")]),
      nodeEvent("load-finish", "test", "flow", "run", "load",
        fekNodeFinished, status = rsSkipped),
      edgeEvent("wait-extract-transform", "test", "flow", "run", "extract-transform",
        fekEdgeWaiting, status = rsCompleted, durationMillis = 500),
      edgeEvent("blocked-transform-load", "test", "flow", "run", "transform-load",
        fekEdgeBlocked, status = rsFailed, durationMillis = 1500)
    ]

    let ops = events.operationalMetrics()
    check ops.executionCount == 3
    check ops.completedExecutionCount == 1
    check ops.failedExecutionCount == 1
    check ops.skippedExecutionCount == 1
    check ops.retryCount == 2
    check ops.workUnits == 100.0
    check ops.acceptedUnits == 98.0
    check ops.defectUnits == 2.0
    check ops.totalCycleTimeMillis == 4000
    check ops.averageCycleTimeMillis == 4000.0 / 3.0
    check ops.totalWaitTimeMillis == 500
    check ops.totalBlockedTimeMillis == 1500
    check ops.totalObservedTimeMillis == 6000
    check abs(ops.failureRate - (100.0 / 3.0)) < 0.000001
    check ops.defectRate == 2.0
    check abs(ops.retryRate - (200.0 / 3.0)) < 0.000001
    check ops.firstPassYield == 98.0
    check ops.throughputPerHour == 600.0

  test "operational metrics ignore invalid or negative metric values":
    let events = @[
      nodeEvent("finish", "test", "flow", "run", "node",
        fekNodeFinished, status = rsCompleted, durationMillis = 100,
        metrics = [kv("records", "bad"), kv("defects", "-2"), kv("retry_count", "1.9")])
    ]

    let ops = events.operationalMetrics()
    check ops.executionCount == 1
    check ops.workUnits == 0.0
    check ops.defectUnits == 0.0
    check ops.retryCount == 1
    check ops.failureRate == 0.0
    check ops.defectRate == 0.0
    check ops.firstPassYield == 0.0

  test "operational metrics are zero for empty input":
    let ops = operationalMetrics([])
    check ops.executionCount == 0
    check ops.totalObservedTimeMillis == 0
    check ops.failureRate == 0.0
    check ops.throughputPerHour == 0.0
