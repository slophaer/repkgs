# closure of jq: the tar, extracted and moved, runs bin/jq. Without /nix/store when the sandbox
# allows a user namespace; otherwise the moved directory alone is the proof (said in the output).
use checks.nu *
use closure.nu
let t = $"($env.TMPDIR? | default /tmp)/closure-test"
mkdir $"($t)/first"
^tar -xf $"($env.tarball)/jq.tar" -C $"($t)/first"
assert "profile has bin/jq" ($"($t)/first/bin/jq" | path type | $in in [symlink file])
assert "closure carries its store" (($"($t)/first/nix/store" | path exists))

# reproducible: owner 0/0 and one fixed mtime on every entry, siblings in name order, and no
# hard links (the store has them only where it was optimised)
let lines = (^tar -tvf $"($env.tarball)/jq.tar" --full-time | lines)
let hard = ($lines | where { $in =~ ' link to ' })
assert $"no hard link entries: ($hard | first 3)" ($hard | is-empty)
let entries = ($lines | parse -r '^\S+ (?<own>\S+)\s+\d+\s+(?<time>\S+ \S+) (?<name>.+?)(?: -> .*)?$')
let owners = ($entries.own | uniq)
assert $"every entry owned by 0/0: ($owners)" ($owners == ["0/0"])
let times = ($entries.time | uniq)
assert $"every entry has the same fixed mtime: ($times)" ($times == ["1970-01-01 00:00:01"])
# depth first with sorted siblings is a plain sort once "/" sorts before every other byte
let key = {|n| $n | str trim -r -c "/" | str replace -a "/" "\u{1}" }
let names = ($entries.name | each { do $key $in })
assert "entries in name order" ($names == ($names | sort))

# moved: not where it was extracted
^mv $"($t)/first" $"($t)/moved"
let jq = $"($t)/moved/bin/jq"
let v = (^env -i $jq --version | str trim)
assert $"moved dir runs jq: ($v)" ($v | str starts-with "jq-")
assert "jq filters" ((^env -i $jq -n "1+2" | str trim) == "3")

# hide /nix/store: an empty tmpfs mounted over it, in a private mount namespace
# mount is found before the store is hidden; jq is exec'd after, with whatever environment sh has
let mnt = (which mount | get path.0)
let hidden = (^unshare -rm sh -c $"($mnt) -t tmpfs none /nix/store && exec ($jq) --version" | complete)
if $hidden.exit_code == 0 {
  assert "with /nix/store hidden jq runs" ($hidden.stdout | str trim | str starts-with "jq-")
  # prove the hiding worked: the original store path of this tar is gone in that namespace
  let gone = (^unshare -rm sh -c $"($mnt) -t tmpfs none /nix/store && test ! -e ($env.tarball)" | complete)
  assert "/nix/store was really hidden" ($gone.exit_code == 0)
  print "closure: relocation proven with /nix/store hidden"
} else {
  print $"closure: no user namespace here, moved-dir proof only: ($hidden.stderr | str trim)"
}

# two roots with the same bin/ name: an error, not the first one silently. The same root twice is fine
let fake = {|n| mkdir $"($t)/($n)/bin"; "" | save -f $"($t)/($n)/bin/x"; $"($t)/($n)" }
let a = (do $fake "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-a")
let b = (do $fake "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-b")
let run = {|roots: list<string>, dir: string|
  mkdir $"($t)/($dir)/top" $"($t)/($dir)/out"
  {closure: ($roots | uniq | each { {path: $in} })} | to json | save -f $"($t)/($dir)/attrs.json"
  with-env {NIX_ATTRS_JSON_FILE: $"($t)/($dir)/attrs.json", NIX_BUILD_TOP: $"($t)/($dir)/top", out: $"($t)/($dir)/out"} {
    closure $roots x
  }
}
do $run [$a $a] same
assert "the same root twice links bin/x once" ($"($t)/same/out/x.tar" | path exists)
fails "two roots with bin/x fail" { do $run [$a $b] dup }
done
