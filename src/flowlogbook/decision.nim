import ./fingerprint
import ./types

proc completedRecord*(
    input: RunInput;
    outputs: openArray[Artifact];
    attempt: Natural = 1;
    message = ""): RunRecord =
  RunRecord(
    fingerprint: fingerprint(input),
    input: input,
    outputs: @outputs,
    status: rsCompleted,
    attempt: attempt,
    message: message
  )

proc failedRecord*(
    input: RunInput;
    attempt: Natural = 1;
    message = ""): RunRecord =
  RunRecord(
    fingerprint: fingerprint(input),
    input: input,
    status: rsFailed,
    attempt: attempt,
    message: message
  )

proc pendingRecord*(
    input: RunInput;
    attempt: Natural = 1;
    message = ""): RunRecord =
  RunRecord(
    fingerprint: fingerprint(input),
    input: input,
    status: rsPending,
    attempt: attempt,
    message: message
  )

proc runningRecord*(
    input: RunInput;
    attempt: Natural = 1;
    message = ""): RunRecord =
  RunRecord(
    fingerprint: fingerprint(input),
    input: input,
    status: rsRunning,
    attempt: attempt,
    message: message
  )

proc skippedRecord*(
    input: RunInput;
    attempt: Natural = 1;
    message = ""): RunRecord =
  RunRecord(
    fingerprint: fingerprint(input),
    input: input,
    status: rsSkipped,
    attempt: attempt,
    message: message
  )

proc canReuse*(record: RunRecord;
    policy: ReusePolicy = defaultReusePolicy()): tuple[ok: bool, reason: string] =
  if record.fingerprint.len == 0:
    return (false, "record has no fingerprint")
  if policy.requireCompleted and record.status != rsCompleted:
    return (false, "previous run is not completed")
  if policy.requireOutputs and record.outputs.len == 0:
    return (false, "previous run has no recorded outputs")
  for output in record.outputs:
    if policy.requirePresentOutputs and not output.present:
      return (false, "previous output is marked missing: " & output.path)
    if policy.requireOutputDigests and output.digest.len == 0:
      return (false, "previous output has no digest: " & output.path)
  (true, "completed run with recorded outputs")

proc reuseDecision*(record: RunRecord;
    policy: ReusePolicy = defaultReusePolicy()): ResumeDecision =
  ResumeDecision(
    kind: rdkReuse,
    fingerprint: record.fingerprint,
    reason: "fingerprint matched: " & canReuse(record, policy).reason,
    record: record,
    hasRecord: true
  )

proc executeDecision*(fingerprint, reason: string; record: RunRecord = RunRecord();
    hasRecord = false): ResumeDecision =
  ResumeDecision(
    kind: rdkExecute,
    fingerprint: fingerprint,
    reason: reason,
    record: record,
    hasRecord: hasRecord
  )
