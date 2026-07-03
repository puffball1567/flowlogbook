import ./types

type
  ValidationResult* = object
    ok*: bool
    reason*: string

proc valid*(): ValidationResult =
  ValidationResult(ok: true, reason: "")

proc invalid*(reason: string): ValidationResult =
  ValidationResult(ok: false, reason: reason)

proc validate*(input: RunInput): ValidationResult =
  if input.taskName.len == 0:
    return invalid("run input taskName must not be empty")
  if input.command.len == 0:
    return invalid("run input command must not be empty")
  valid()

proc validate*(record: RunRecord): ValidationResult =
  if record.fingerprint.len == 0:
    return invalid("run record fingerprint must not be empty")
  if record.input.taskName.len == 0:
    return invalid("run record input taskName must not be empty")
  valid()

proc validate*(event: FlowEvent): ValidationResult =
  if event.id.len == 0:
    return invalid("flow event id must not be empty")
  if event.flowId.len == 0:
    return invalid("flow event flowId must not be empty")
  if event.runId.len == 0:
    return invalid("flow event runId must not be empty")
  if event.nodeId.len == 0 and event.edgeId.len == 0 and event.kind != fekNote:
    return invalid("flow event nodeId or edgeId must not be empty")
  valid()

proc requireValid*(record: RunRecord) =
  let checked = validate(record)
  if not checked.ok:
    raise newException(ValueError, checked.reason)

proc requireValid*(event: FlowEvent) =
  let checked = validate(event)
  if not checked.ok:
    raise newException(ValueError, checked.reason)
