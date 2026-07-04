# Integration

FlowLogbook is intended to be embedded by FlowCaptain or other coordination
tools as the execution ledger.

## Recommended Boundary

Use `LogbookInput` when an adapter wants to submit records and events as a
single validated unit:

```nim
import flowlogbook

let input = initLogbookInput(records = records, events = events)
let outcome = validate(input)

if outcome.ok:
  persist(records, events)
else:
  reject(outcome.errors)
```

This keeps validation separate from the selected storage backend. Callers can
choose memory, SQLite, PostgreSQL, Redis, or a custom adapter after the input has
been accepted.

## Adapter Responsibility

Adapters should map native runner, workflow, database, or external telemetry
records into `RunRecord` and `FlowEvent`. FlowLogbook validates required fields,
but it does not decide whether an external system is trustworthy.
