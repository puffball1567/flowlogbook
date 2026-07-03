import std/algorithm

import ./types

const FnvOffset = 0xcbf29ce484222325'u64
const FnvPrime = 0x100000001b3'u64

proc update(hash: var uint64; text: string) =
  for ch in text:
    hash = hash xor uint64(ord(ch))
    hash = hash * FnvPrime

proc hex64(value: uint64): string =
  const digits = "0123456789abcdef"
  result = newString(16)
  for i in countdown(15, 0):
    result[15 - i] = digits[int((value shr (i * 4)) and 0xFu64)]

proc sortedPairs(values: seq[KeyValue]): seq[KeyValue] =
  result = values
  result.sort(proc(a, b: KeyValue): int =
    result = cmp(a.key, b.key)
    if result == 0:
      result = cmp(a.value, b.value)
  )

proc sortedArtifacts(values: seq[Artifact]): seq[Artifact] =
  result = values
  result.sort(proc(a, b: Artifact): int =
    result = cmp(a.path, b.path)
    if result == 0:
      result = cmp(a.digest, b.digest)
  )

proc addField(hash: var uint64; name, value: string) =
  hash.update(name)
  hash.update("\0")
  hash.update(value)
  hash.update("\n")

proc fingerprint*(input: RunInput): string =
  var hash = FnvOffset
  hash.addField("taskName", input.taskName)
  hash.addField("command", input.command)
  hash.addField("implementation", input.implementation)

  for item in sortedArtifacts(input.inputs):
    hash.addField("input.path", item.path)
    hash.addField("input.digest", item.digest)
    hash.addField("input.present", $item.present)

  for item in sortedPairs(input.params):
    hash.addField("param.key", item.key)
    hash.addField("param.value", item.value)

  for item in sortedPairs(input.env):
    hash.addField("env.key", item.key)
    hash.addField("env.value", item.value)

  "fnv1a64:" & hex64(hash)
