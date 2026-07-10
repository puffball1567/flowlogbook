import std/strutils

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


  OperationalMetrics* = object
    executionCount*: Natural
    completedExecutionCount*: Natural
    failedExecutionCount*: Natural
    skippedExecutionCount*: Natural
    retryCount*: Natural
    workUnits*: float
    acceptedUnits*: float
    defectUnits*: float
    totalCycleTimeMillis*: Natural
    averageCycleTimeMillis*: float
    totalWaitTimeMillis*: Natural
    totalBlockedTimeMillis*: Natural
    totalObservedTimeMillis*: Natural
    throughputPerHour*: float
    failureRate*: float
    defectRate*: float
    retryRate*: float
    firstPassYield*: float

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


proc metricNumber(item: FlowEvent; names: openArray[string]): float =
  for metric in item.metrics:
    let key = metric.key.strip().toLowerAscii()
    for name in names:
      if key == name:
        try:
          let value = parseFloat(metric.value.strip())
          if value >= 0.0:
            return value
        except ValueError:
          discard
  0.0

proc metricNatural(item: FlowEvent; names: openArray[string]): Natural =
  let value = metricNumber(item, names)
  if value <= 0.0:
    return 0
  Natural(value.int)

proc ratio(numerator, denominator: float): float =
  if denominator <= 0.0:
    return 0.0
  numerator / denominator * 100.0

proc operationalMetrics*(events: openArray[FlowEvent]): OperationalMetrics =
  for item in events:
    if item.nodeId.len > 0 and item.kind == fekNodeFinished:
      result.executionCount.inc
      if item.durationMillis > 0:
        result.totalCycleTimeMillis.inc item.durationMillis

    case item.status
    of rsCompleted:
      if item.nodeId.len > 0 and item.kind == fekNodeFinished:
        result.completedExecutionCount.inc
    of rsFailed:
      if item.nodeId.len > 0 and item.kind == fekNodeFinished:
        result.failedExecutionCount.inc
    of rsSkipped:
      if item.nodeId.len > 0 and item.kind == fekNodeFinished:
        result.skippedExecutionCount.inc
    else:
      discard

    if item.edgeId.len > 0:
      case item.kind
      of fekEdgeWaiting:
        result.totalWaitTimeMillis.inc item.durationMillis
      of fekEdgeBlocked:
        result.totalBlockedTimeMillis.inc item.durationMillis
      else:
        discard

    result.workUnits += metricNumber(item, ["work", "work_units", "units", "records", "items"])
    result.acceptedUnits += metricNumber(item, ["accepted", "accepted_units", "good", "good_units", "passed"])
    result.defectUnits += metricNumber(item, ["defects", "defect_units", "rejected", "rejected_units", "failed_units"])
    result.retryCount.inc metricNatural(item, ["retry", "retries", "retry_count", "attempt_retries"])

  result.totalObservedTimeMillis = result.totalCycleTimeMillis +
    result.totalWaitTimeMillis + result.totalBlockedTimeMillis

  if result.executionCount > 0:
    result.averageCycleTimeMillis = result.totalCycleTimeMillis.float /
      result.executionCount.float
    result.failureRate = ratio(result.failedExecutionCount.float,
      result.executionCount.float)
    result.retryRate = ratio(result.retryCount.float, result.executionCount.float)

  let completedAndDefect = result.acceptedUnits + result.defectUnits
  if completedAndDefect > 0.0:
    result.defectRate = ratio(result.defectUnits, completedAndDefect)
    result.firstPassYield = ratio(result.acceptedUnits, completedAndDefect)

  if result.totalObservedTimeMillis > 0:
    result.throughputPerHour = result.completedExecutionCount.float /
      (result.totalObservedTimeMillis.float / 3600000.0)
