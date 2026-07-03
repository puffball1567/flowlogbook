# IP Notes

FlowLogbook is designed around public, general software engineering concepts:

- content and configuration fingerprints
- execution records
- cache hit and cache miss decisions
- explicit status values
- output metadata
- append-only event or record history
- caller-selected reuse policy
- node and edge event records
- local persistence through SQLite
- server persistence through PostgreSQL and Redis-compatible adapters

The implementation is intentionally original and small. It does not copy code,
data structures, DSL syntax, or internal behavior from Nextflow or other
workflow systems.

The SQLite and PostgreSQL adapters call public C client APIs through minimal
internal FFI layers. The Redis-compatible adapter uses the documented RESP
command protocol. Database client handles are not exposed through FlowLogbook
public records or events.

If a credible concern is raised, the maintainers should review the affected
feature, document the finding, and remove or redesign the feature if needed.
