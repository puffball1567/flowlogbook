import ./types

type
  EventMetrics* = object
    eventCount*: Natural
    nodeEventCount*: Natural
    edgeEventCount*: Natural
    metricEventCount*: Natural
    metricValueCount*: Natural
    completedCount*: Natural
    failedCount*: Natural
    skippedCount*: Natural
    totalDurationMillis*: Natural
    eventsWithTiming*: Natural
    eventsWithMetrics*: Natural
    metricDensity*: float
    timingCoverage*: float

proc eventMetrics*(events: openArray[FlowEvent]): EventMetrics =
  result.eventCount = Natural(events.len)
  for item in events:
    if item.nodeId.len > 0:
      result.nodeEventCount.inc
    if item.edgeId.len > 0:
      result.edgeEventCount.inc
    if item.kind == fekMetric:
      result.metricEventCount.inc
    if item.metrics.len > 0:
      result.eventsWithMetrics.inc
      result.metricValueCount.inc Natural(item.metrics.len)
    if item.durationMillis > 0:
      result.eventsWithTiming.inc
      result.totalDurationMillis.inc item.durationMillis
    case item.status
    of rsCompleted:
      result.completedCount.inc
    of rsFailed:
      result.failedCount.inc
    of rsSkipped:
      result.skippedCount.inc
    else:
      discard

  if events.len > 0:
    result.metricDensity = result.metricValueCount.float / events.len.float
    result.timingCoverage = result.eventsWithTiming.float / events.len.float * 100.0
