import flowlogbook

let input = runInput(
  taskName = "thumbnail",
  command = "convert input.png -resize 256x256 output.png",
  inputs = @[artifact("input.png", "sha256:source")],
  params = @[kv("size", "256")]
)

var ledger = initMemoryLedger()
doAssert ledger.decide(input).kind == rdkExecute

ledger.record(completedRecord(input, @[artifact("output.png", "sha256:out")]))
doAssert ledger.decide(input).kind == rdkReuse
