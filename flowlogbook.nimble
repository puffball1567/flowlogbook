version       = "0.2.0"
author        = "flowlogbook contributors"
description   = "Execution ledger and resume-decision primitives for repeatable tasks."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @[
  ".github",
  "benchmarks",
  "docs",
  "examples",
  "tests"
]

requires "nim >= 2.2.0"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowlogbook-test-nimcache -p:src tests/all.nim"

task examples, "Check examples":
  exec "nim check --nimcache:/tmp/flowlogbook-nimcache -p:src examples/basic_resume.nim"
  exec "nim check --nimcache:/tmp/flowlogbook-nimcache -p:src examples/sqlite_persistence.nim"
  exec "nim check --nimcache:/tmp/flowlogbook-nimcache -p:src examples/postgres_persistence.nim"
  exec "nim check --nimcache:/tmp/flowlogbook-nimcache -p:src examples/redis_persistence.nim"
  exec "nim check --nimcache:/tmp/flowlogbook-nimcache -p:src examples/external_events.nim"

task bench, "Run basic local benchmarks":
  exec "nim r -d:release --nimcache:/tmp/flowlogbook-bench-nimcache -p:src benchmarks/basic_ledger.nim"
