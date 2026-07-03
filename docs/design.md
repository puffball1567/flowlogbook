# Design

FlowLogbook is a ledger for repeatable execution units.

## Goals

- Represent a task input deterministically.
- Compute a stable fingerprint from task identity, command, inputs, params,
  environment, and implementation version.
- Store completed, failed, skipped, or running records.
- Keep an append-only history per fingerprint.
- Store node and edge events from native execution or external observation.
- Decide whether a new request should execute or reuse a prior record.
- Explain every decision with a reason string.
- Let callers tune reuse policy without changing the stored record format.

## Non-goals

- Workflow DSL
- DAG scheduling
- Container execution
- HPC or cloud executor integration
- Distributed storage
- Filesystem scanning

Those can be built above FlowLogbook.

## Core Model

```text
RunInput
  -> fingerprint
  -> Ledger history lookup
  -> Latest RunRecord
  -> ResumeDecision
```

A prior run can be reused only when:

- the fingerprint matches,
- the previous status is completed,
- at least one output is recorded,
- no output is marked missing.

Everything else returns an execute decision with an explicit reason.

Callers can relax or strengthen this through `ReusePolicy`. For example,
side-effect-only tasks may allow empty outputs, while artifact-sensitive tasks
may require every output to carry a digest.

The ledger stores records append-only per fingerprint. This keeps failed,
running, skipped, and completed attempts visible without forcing FlowLogbook to
become a workflow scheduler or executor.

## Storage

FlowLogbook currently provides:

```text
MemoryLedger
  In-process storage for tests, short-lived tools, and embedded use.

SqliteLedger
  Durable local storage backed by SQLite through a small internal C FFI layer.

PostgresLedger
  Durable server storage backed by libpq parameterized execution.

RedisLedger
  Durable or semi-durable server storage backed by Redis/Valkey-compatible
  lists and index lists through a small built-in RESP client.
```

Database handles are intentionally hidden behind FlowLogbook APIs. Callers
should not depend on SQLite, PostgreSQL, or Redis-compatible client handles. This
makes the adapters usable from Nim while keeping a future C ABI boundary simple:
opaque handles, strings, status codes, and JSON payloads.

The adapters store the canonical record or event as FlowLogbook JSON and keep
small search columns or keys for common lookup paths. This favors simple
portability over database-specific query features.

Durable adapters expose a schema version so future migrations can be explicit
instead of inferred from table shape. The initial storage schema is version 1.

## Flow Events

FlowLogbook also accepts flow events that are not tied to a single `RunInput`.
These events are intended for node/edge-level evidence from FlowWorkRunner,
Nextflow traces, Airflow runs, web framework middleware, business systems, or
scheduled collection jobs.

```text
FlowEvent
  id
  source
  flowId
  runId
  variantId
  nodeId
  edgeId
  kind
  status
  startedAt
  finishedAt
  durationMillis
  metrics
  message
```

This keeps FlowLogbook useful in both modes:

```text
native execution
  FlowCaptain and FlowWorkRunner generate records and events directly.

external observation
  Adapters import events from existing workflow engines, web systems, or
  company business processes.
```

FlowSurveyor can later combine these events with FlowDependency graphs to
calculate critical paths, wait propagation, retry cost, and variant comparison.
