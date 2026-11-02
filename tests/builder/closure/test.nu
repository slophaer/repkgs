# closure of jq: the tar, extracted and moved, runs bin/jq. Without /nix/store when the sandbox
# allows a user namespace; otherwise the moved directory alone is the proof (said in the output).
use checks.nu *
let t = $"($env.TMPDIR? | default /tmp)/closure-test"
mkdir $"($t)/first"
^tar -xf $"($env.tarball)/jq.tar" -C $"($t)/first"
assert "profile has bin/jq" ($"($t)/first/bin/jq" | path type | $in in [symlink file])
assert "closure carries its store" (($"($t)/first/nix/store" | path exists))

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
done
