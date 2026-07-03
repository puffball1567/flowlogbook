import std/tables

import ./decision
import ./fingerprint
import ./types
import ./validation

type
  MemoryLedger* = object
    records: Table[string, seq[RunRecord]]
    events: seq[FlowEvent]

proc initMemoryLedger*(): MemoryLedger =
  MemoryLedger(
    records: initTable[string, seq[RunRecord]](),
    events: @[]
  )

proc record*(ledger: var MemoryLedger; record: RunRecord) =
  requireValid(record)
  if not ledger.records.hasKey(record.fingerprint):
    ledger.records[record.fingerprint] = @[]
  ledger.records[record.fingerprint].add(record)

proc contains*(ledger: MemoryLedger; fingerprint: string): bool =
  ledger.records.hasKey(fingerprint)

proc history*(ledger: MemoryLedger; fingerprint: string): seq[RunRecord] =
  if not ledger.records.hasKey(fingerprint):
    return @[]
  ledger.records[fingerprint]

proc get*(ledger: MemoryLedger; fingerprint: string): RunRecord =
  let records = ledger.history(fingerprint)
  if records.len == 0:
    raise newException(KeyError, "run record not found: " & fingerprint)
  records[^1]

proc attempts*(ledger: MemoryLedger; fingerprint: string): int =
  ledger.history(fingerprint).len

proc recordEvent*(ledger: var MemoryLedger; event: FlowEvent) =
  requireValid(event)
  ledger.events.add(event)

proc events*(ledger: MemoryLedger): seq[FlowEvent] =
  ledger.events

proc eventsForRun*(ledger: MemoryLedger; runId: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.runId == runId:
      result.add(event)

proc eventsForFlow*(ledger: MemoryLedger; flowId: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.flowId == flowId:
      result.add(event)

proc eventsForVariant*(ledger: MemoryLedger; variantId: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.variantId == variantId:
      result.add(event)

proc eventsForNode*(ledger: MemoryLedger; nodeId: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.nodeId == nodeId:
      result.add(event)

proc eventsForEdge*(ledger: MemoryLedger; edgeId: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.edgeId == edgeId:
      result.add(event)

proc eventsBySource*(ledger: MemoryLedger; source: string): seq[FlowEvent] =
  for event in ledger.events:
    if event.source == source:
      result.add(event)

proc eventsByKind*(ledger: MemoryLedger; kind: FlowEventKind): seq[FlowEvent] =
  for event in ledger.events:
    if event.kind == kind:
      result.add(event)

proc eventsByStatus*(ledger: MemoryLedger; status: RunStatus): seq[FlowEvent] =
  for event in ledger.events:
    if event.status == status:
      result.add(event)

proc decide*(ledger: MemoryLedger; input: RunInput;
    policy: ReusePolicy = defaultReusePolicy()): ResumeDecision =
  let fp = fingerprint(input)
  if not ledger.records.hasKey(fp):
    return executeDecision(fp, "no prior run record")

  let prior = ledger.get(fp)
  let reusable = canReuse(prior, policy)
  if reusable.ok:
    return reuseDecision(prior, policy)

  executeDecision(fp, reusable.reason, prior, hasRecord = true)
