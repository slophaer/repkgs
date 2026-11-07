# a compile failure replayed from the cache still writes the depfile the caller asked for
use checks.nu *
let got = (open $"($env.pkg)/share/runs.json")
let dep_runs = ($got.runs | where run != nodep)
for r in $dep_runs {
  let what = $"passthrough=($r.passthrough) seeded=($r.seeded) ($r.run) run \(($r.outcome)\)"
  assert $"($what): the compile fails" ($r.status != 0)
  assert $"($what): leaves the depfile" ($r.depfile != null)
  assert $"($what): the depfile names the object and the header" ($r.depfile =~ '^t\.o:' and ($r.depfile | str contains "t.h"))
}
assert "nodep run: fails, writes no depfile" ($got.runs | where run == nodep | all {|r| $r.status != 0 and $r.depfile == null })
# without jigd every run compiles for real: only the checks above apply
if $got.cache {
  assert "nodep run: the failure is stored" ($got.runs | where run == nodep | all {|r| $r.outcome == compiled-error })
  for r in ($dep_runs | where run == second) {
    assert $"passthrough=($r.passthrough) seeded=($r.seeded): the second run is a replay, not ($r.outcome)" ($r.outcome == cached-error)
  }
  # a stored failure without a depfile is a miss for a run that wants one
  for r in ($dep_runs | where {|r| $r.seeded and $r.run == first }) {
    assert $"seeded first run: compiles again, not ($r.outcome) ($r.subject)" ($r.outcome == compiled-error and ($r.subject | str ends-with object-gone))
  }
}
done
