# a rustc cache hit from another Cargo.lock writes a dep-info naming this build's vendor tree
use checks.nu *
let got = (open $"($env.pkg)/share/runs.json")
assert "the dependency's dep-info exists" ($got.depfiles | is-not-empty)
for d in $got.depfiles {
  assert $"($d.name) names the vendor tree of this build" ($d.text | str contains $got.vendor_b)
  assert $"($d.name) does not name the vendor tree of the build that filled the cache" (not ($d.text | str contains $got.vendor_a))
}
# without jigd every crate compiles for real: only the checks above apply
if $got.cache {
  let last = ($got.rustc | last)
  assert $"the dependency is replayed from the cache, not ($last.outcome)" ($last.outcome == cached)
}
done
