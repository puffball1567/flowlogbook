# FlowLogbook

FlowLogbook is a small Nim library for recording repeatable task executions and
making resume decisions.

It is not a workflow engine. It does not schedule tasks, run containers, or
manage a DAG. It focuses on one reusable layer:

```text
given a task identity and recorded outputs, should this run execute again or
reuse a previous result?
```

This is useful for workflow tools, batch jobs, AI pipelines, build tools, ETL
steps, and delivery systems that need auditable execution records.

## Status

FlowLogbook v0.3.1 is focused on execution records, resume decisions,
adapter-friendly event history, and event-quality metrics. Within that scope,
the current version provides:

- deterministic task fingerprints
- structured run inputs and output artifacts
- append-only in-memory ledger storage
- SQLite ledger storage through a small internal SQLite C FFI adapter
- PostgreSQL ledger storage through libpq
- Redis/Valkey-compatible ledger storage through a small built-in RESP client
- explicit schema version metadata for durable stores
- latest-record lookup plus full history access
- node and edge events for executed or externally observed flows
- event metrics for timing coverage, metric density, node/edge event counts,
  metric event counts, and total observed duration
- operational metrics for cycle time, wait/blocking time, throughput, failure
  rate, defect rate, retry rate, and first-pass yield
- FlowCaptain-style batch validation through `LogbookInput`
- resume decisions with explicit reasons
- reusable policy controls for output and digest requirements
- focused tests for cache hit, miss, failed run, missing output, and invalid
  fingerprints

## Requirements

Core in-memory usage only needs Nim.

SQLite persistence uses the system SQLite C library and headers. On Ubuntu:

```bash
sudo apt install libsqlite3-dev
```

PostgreSQL persistence uses the system libpq runtime library. On Ubuntu:

```bash
sudo apt install libpq5
```

Redis/Valkey-compatible persistence only needs a reachable RESP server.
FlowLogbook speaks RESP directly from Nim and does not require hiredis.
The current RESP adapter targets single-node servers. TLS, Sentinel, Cluster,
and server-side Lua scripts are outside the built-in adapter scope.

## Example

```nim
import flowlogbook

let input = runInput(
  taskName = "thumbnail",
  command = "convert input.png -resize 256x256 output.png",
  inputs = @[artifact("input.png", "sha256:source")],
  params = @[kv("size", "256")]
)

var ledger = initMemoryLedger()
let first = ledger.decide(input)
doAssert first.kind == rdkExecute

let completed = completedRecord(input, @[artifact("output.png", "sha256:out")])
ledger.record(completed)

let second = ledger.decide(input)
doAssert second.kind == rdkReuse
doAssert ledger.attempts(fingerprint(input)) == 1
```

Use SQLite when records should survive process restarts:

```nim
import flowlogbook/sqlite_store

var persistent = openSqliteLedger("flowlogbook.sqlite3")
persistent.record(completed)
let reused = persistent.decide(input)
persistent.close()
```

PostgreSQL and Redis/Valkey-compatible storage are available as optional
modules:

```nim
import flowlogbook/postgres_store
import flowlogbook/redis_store

var pg = openPostgresLedger("host=127.0.0.1 dbname=flowlogbook user=flowlogbook")
var redis = openRedisLedger(host = "127.0.0.1", keyPrefix = "flowlogbook")
```

SQLite and PostgreSQL adapters expose explicit transactions for bulk writes:

```nim
persistent.beginTransaction()
try:
  persistent.record(completed)
  persistent.commitTransaction()
except:
  persistent.rollbackTransaction()
  raise
```

Reuse policy can be adjusted for tasks whose success is represented by a
side effect rather than a file output:

```nim
var policy = defaultReusePolicy()
policy.requireOutputs = false

let decision = ledger.decide(input, policy)
```

FlowLogbook can also record flow events that come from a runner, a web
framework adapter, or an external workflow system:

```nim
ledger.recordEvent(nodeEvent(
  id = "evt-1",
  source = "nextflow-trace",
  flowId = "pipeline",
  runId = "run-1",
  variantId = "A",
  nodeId = "align",
  kind = fekNodeFinished,
  status = rsCompleted,
  durationMillis = 1200,
  metrics = @[kv("records", "42")]
))
```

Event metrics can be calculated from collected flow events:

```nim
let metrics = events.eventMetrics()
echo metrics.timingCoverage
echo metrics.metricDensity
```

Operational metrics can be calculated from the same events when a caller wants
to analyze throughput, cycle time, wait time, failure rate, defect rate, retry
rate, or first-pass yield across a flow:

```nim
let ops = events.operationalMetrics()
echo ops.averageCycleTimeMillis
echo ops.throughputPerHour
echo ops.defectRate
```

For component integration, validate records and events as a batch before
persisting them:

```nim
let input = initLogbookInput(records = @[completed], events = @[
  nodeEvent("evt-2", "runner", "flow", "run-1", "publish", fekNodeFinished,
    status = rsCompleted)
])
let outcome = validate(input)
doAssert outcome.ok
```

More examples are available in `examples/`:

- `basic_resume.nim`
- `sqlite_persistence.nim`
- `postgres_persistence.nim`
- `redis_persistence.nim`
- `external_events.nim`

## Relationship To FlowBrigade

FlowBrigade controls execution while it is happening: retry, timeout, rate
limit, bulkhead, lock, and budget.

FlowLogbook records what happened before and after execution: task identity,
outputs, status, and whether an existing result can be reused.

It can also record observed node and edge events. This lets external tools such
as workflow engines, web framework adapters, and business data collectors feed
evidence into the same logbook model.

They are designed to compose without either project depending on the other.

## Scope

FlowLogbook deliberately stays below workflow engines. It can be used by a
workflow runtime, a web job runner, a build tool, an AI pipeline, or a delivery
system without adopting a specific DSL, scheduler, container backend, or cloud
service.

The SQLite adapter keeps SQLite handles private to FlowLogbook. Public APIs
use FlowLogbook records, events, and JSON strings instead of exposing database
client handles. PostgreSQL and Redis/Valkey-compatible adapters follow the same public
API shape. This keeps future C ABI bindings simpler and safer.

## Security Notes

FlowLogbook validates records and events before storing them. JSON import rejects
unknown enum values, negative natural-number fields, and non-array values where
arrays are required.

SQLite writes use prepared statements. PostgreSQL writes use libpq parameterized
execution. Redis/Valkey-compatible commands are encoded as RESP frames and do
not pass through a shell.

Callers are still responsible for choosing trusted database paths, limiting
untrusted JSON input size before parsing, controlling filesystem permissions for
SQLite files, protecting database credentials, and using TLS or private networks
when connecting to external database servers.

Live adapter tests are opt-in so normal test runs do not require local services:

```bash
FLOWLOGBOOK_TEST_REDIS=1 nimble test
FLOWLOGBOOK_TEST_POSTGRES=1 FLOWLOGBOOK_POSTGRES_CONNINFO='host=127.0.0.1 dbname=flowlogbook_test user=flowlogbook' nimble test
```

Run the ARC leak probe with Valgrind:

```bash
nimble leak
```

The leak probe builds a release binary under Nim ARC and fails on definite or
indirect leaks reported by Valgrind.

For a disposable PostgreSQL test database:

```bash
docker run --rm --name flowlogbook-postgres \
  -e POSTGRES_PASSWORD=flowlogbook \
  -e POSTGRES_USER=flowlogbook \
  -e POSTGRES_DB=flowlogbook_test \
  -p 5432:5432 postgres:16

FLOWLOGBOOK_TEST_POSTGRES=1 \
FLOWLOGBOOK_POSTGRES_CONNINFO='host=127.0.0.1 port=5432 dbname=flowlogbook_test user=flowlogbook password=flowlogbook' \
nimble test
```

Basic local benchmarks are available:

```bash
nimble bench
```

Benchmarks are intended as regression signals, not vendor-neutral database
benchmarks. The SQLite benchmark uses an explicit transaction because one
durable commit per record measures sync overhead more than ledger overhead.

## Intellectual Property Notes

FlowLogbook intentionally uses general, well-known ideas: deterministic hashes,
task records, output metadata, and explicit cache/resume decisions. It is not a
copy of Nextflow or any other workflow engine.

See [docs/ip-notes.md](docs/ip-notes.md).
