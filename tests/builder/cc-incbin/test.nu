# `.incbin` reads a file no depfile names: a cached object must not outlive a change of that file
use checks.nu *
let got = (open $"($env.pkg)/share/runs.json")
for r in ($got.runs | where case not-in [missing comment]) {
  let what = $"($r.case) run ($r.run) \(($r.outcome)\)"
  assert $"($what): compiles" ($r.status == 0)
  # the second run has other data in data.bin and must show it, cache or not
  assert $"($what): the object holds the data of this run" (if $r.run == 1 { $r.has_a and not $r.has_b } else { $r.has_b and not $r.has_a })
}
# a failure for a missing .incbin file must not be replayed once the file exists
let missing = ($got.runs | where case == missing)
assert "missing: the first run fails" ($missing.0.status != 0)
assert $"missing: the run with the file works \(($missing.1.outcome)\)" ($missing.1.status == 0 and $missing.1.has_b)
# without jigd every run compiles for real: only the checks above apply
if $got.cache {
  for r in ($got.runs | where run == 2 and case not-in [missing comment]) {
    assert $"($r.case): the second run is not a replay, but ($r.outcome)" ($r.outcome not-in [cached cached-error])
  }
}
# words in comments read no file: the comment case compiles, and its second run is a replay
for r in ($got.runs | where case == comment) { assert $"comment run ($r.run): compiles" ($r.status == 0) }
if $got.cache {
  let second = ($got.runs | where case == comment and run == 2 | first)
  assert $"comment: the second run is a replay, not ($second.outcome)" ($second.outcome == cached)
}
done
