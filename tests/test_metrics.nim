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
