# nix-build tests/uptrack.nix; also runnable with the source and checks directories on NU_LIB_DIRS.
use checks.nu *
use pipeline.nu
use datasource.nu

let old = "1111111111111111111111111111111111111111"
let new = "2222222222222222222222222222222222222222"
def package [purl: string, candidate: record] {
  {name: demo, upstream: {purl: $purl}, watch: {}, pin: {version: "20261101.120000", rev: $old},
    candidates: [$candidate], error: null, source: [{key: default, url: 'https://example.test/{rev}.tar.gz'}]}
}
for version in ["20261101.120000" "20261031.120000"] {
  let c = {version: $version, date: "2026-10-31T12:00:00Z", rev: $new, prerelease: false}
  for source in ["pkg:git/demo?url=https://example.test/demo.git&ref=main" "pkg:github/demo/repo?branch=main"] {
    let update = (pipeline decide [(package $source $c)] | first)
    assert $"head updates on revision change, version=($version) source=($source)" ($update.to == $version and $update.pin.rev == $new)
    assert "source URL uses revision" ($update.sources.0.url == $"https://example.test/($new).tar.gz")
  }
}
let unchanged = (pipeline decide [(package "pkg:git/demo?url=https://example.test/demo.git" {version: "20261102.120000", date: null, rev: $old, prerelease: false})] | first)
assert "same revision does not update" ($unchanged.to == null)
let release = (pipeline decide [(package "pkg:github/demo/repo" {version: "20261031.120000", date: null, rev: $new, prerelease: false})] | first)
assert "ordinary release ordering stays intact" ($release.to == null)
let held = (package "pkg:github/demo/repo?branch=main" {version: "20261101.120000", date: (date now | format date '%+'), rev: $new, prerelease: false} | upsert upstream.every "1day")
assert "head still obeys age filter" ((pipeline decide [$held] | first | get to) == null)

let root = (mktemp -d -t uptrack-test.XXXX)
mkdir $"($root)/repo" $"($root)/tmp" $"($root)/cache"
^git -C $"($root)/repo" init -q --initial-branch=main
"first" | save $"($root)/repo/file"
^git -C $"($root)/repo" add file
with-env {GIT_AUTHOR_DATE: "2026-11-01T12:00:00Z", GIT_COMMITTER_DATE: "2026-11-01T12:00:00Z"} {
  ^git -C $"($root)/repo" -c user.name=Test -c user.email=test@example.test -c commit.gpgsign=false commit -qm first
}
let first = (^git -C $"($root)/repo" rev-parse HEAD | str trim)
"second" | save -f $"($root)/repo/file"
^git -C $"($root)/repo" add file
with-env {GIT_AUTHOR_DATE: "2026-11-01T12:00:00Z", GIT_COMMITTER_DATE: "2026-11-01T12:00:00Z"} {
  ^git -C $"($root)/repo" -c user.name=Test -c user.email=test@example.test -c commit.gpgsign=false commit -qm second
}
let second = (^git -C $"($root)/repo" rev-parse HEAD | str trim)
assert "fixture has distinct same-second commits" ($first != $second)
let p = {type: git, namespace: "", name: demo, qualifiers: {url: $"file://($root)/repo", ref: main}}
let head = (with-env {TMPDIR: $"($root)/tmp"} { datasource versions $p } | first)
assert "local git branch resolves actual revision" ($head.rev == $second and $head.version == "20261101.120000")
assert "git temp directory removed after success" ((glob $"($root)/tmp/*") | is-empty)

# Pre-fill the real HTTP cache. No credentials or network are needed for the GitHub branch test.
let branch = "feature/test"
let url = $"https://api.github.com/repos/demo/repo/commits/($branch | url encode --all)"
mkdir $"($root)/cache/uptrack"
{fetched: (date now | format date '%+'), body: {sha: $second, commit: {committer: {date: "2026-11-01T12:00:00Z"}}}}
  | to json | save $"($root)/cache/uptrack/($url | hash sha256)"
let gh = (with-env {XDG_CACHE_HOME: $"($root)/cache"} {
  datasource versions {type: github, namespace: demo, name: repo, qualifiers: {branch: $branch}}
} | first)
assert "GitHub branch uses cached API candidate" ($gh.rev == $second and $gh.version == $head.version)

# A real fast-forward can move the display timestamp backwards.
"third" | save -f $"($root)/repo/file"
^git -C $"($root)/repo" add file
with-env {GIT_AUTHOR_DATE: "2026-10-31T12:00:00Z", GIT_COMMITTER_DATE: "2026-10-31T12:00:00Z"} {
  ^git -C $"($root)/repo" -c user.name=Test -c user.email=test@example.test -c commit.gpgsign=false commit -qm third
}
let backward = (with-env {TMPDIR: $"($root)/tmp"} { datasource versions $p } | first)
let followed = (pipeline decide [(package "pkg:git/demo?url=https://example.test/demo.git" $backward | upsert pin.rev $second)] | first)
assert "fast-forward with older time updates" ($followed.to == "20261031.120000" and $followed.pin.rev == $backward.rev)

# Fail each subprocess and check both short-circuiting and cleanup.
let git = (which git | get path.0)
mkdir $"($root)/stub"
($"#!($nu.current-exe) --no-config-file\n" + 'def --wrapped main [...args: string] {
  let phase = ($args | where { $in in [init fetch log] } | first)
  $phase + "\n" | save --append $env.GIT_CALL_LOG
  if $phase == $env.FAIL_PHASE { print -e "injected git failure"; exit 7 }
  let r = (^$env.REAL_GIT ...$args | complete)
  print --no-newline $r.stdout
  print -e --no-newline $r.stderr
  exit $r.exit_code
}
') | save $"($root)/stub/git"
^chmod +x $"($root)/stub/git"
for phase in [init fetch log] {
  let calls = $"($root)/($phase).calls"
  let r = (with-env {TMPDIR: $"($root)/tmp", PATH: ([$"($root)/stub"] ++ $env.PATH), REAL_GIT: $git, FAIL_PHASE: $phase, GIT_CALL_LOG: $calls} {
    try { datasource versions $p; {failed: false} } catch {|e| {failed: true, message: $e.msg} }
  })
  assert $"git ($phase) failure propagates" $r.failed
  assert $"git ($phase) error names failure" ($r.message | str contains "injected git failure")
  let expected = ([init fetch log] | take (([init fetch log] | enumerate | where item == $phase | first | get index) + 1))
  assert $"git ($phase) short-circuits" ((open --raw $calls | lines) == $expected)
  assert $"git ($phase) removes temp directory" ((glob $"($root)/tmp/*") | is-empty)
}
rm -rf $root
print "uptrack: revision identity, release ordering, age filter, local Git, cached GitHub, subprocess failures and cleanup pass"
done
