import ./types
import ./validation

type
  LogbookInput* = object
    records*: seq[RunRecord]
    events*: seq[FlowEvent]

  LogbookOutcome* = object
    ok*: bool
    acceptedRecords*: Natural
    acceptedEvents*: Natural
    errors*: seq[string]

proc initLogbookInput*(records: openArray[RunRecord] = [];
    events: openArray[FlowEvent] = []): LogbookInput =
  LogbookInput(records: @records, events: @events)

proc validate*(input: LogbookInput): LogbookOutcome =
  var errors: seq[string]

  for index, record in input.records:
    let validation = validate(record)
    if not validation.ok:
      errors.add("record[" & $index & "]: " & validation.reason)

  for index, event in input.events:
    let validation = validate(event)
    if not validation.ok:
      errors.add("event[" & $index & "]: " & validation.reason)

  LogbookOutcome(
    ok: errors.len == 0,
    acceptedRecords: if errors.len == 0: input.records.len else: 0,
    acceptedEvents: if errors.len == 0: input.events.len else: 0,
    errors: errors
  )
