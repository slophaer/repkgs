# A wrapper of a wrapper: both write share/wrap/<pname>/ (the same pname). The outer one must get
# its own copy-on-write directory there, never write through a link into the inner tree.
# Seed only: a synthetic package without bin/, the real wrap module, attrs written here.
use checks.nu *
use wrap.nu

let real_out = $env.out
let t = $"($env.TMPDIR? | default /tmp)/wrap-tree"
# store-like names: wrap.nu takes the package name from after the 32-character hash
let pkg = $"($t)/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-thing-1"
let inner = $"($t)/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-thing-1-wrap"
let outer = $"($t)/cccccccccccccccccccccccccccccccc-thing-1-wrap"
mkdir $"($pkg)/share/data"
"docs\n" | save $"($pkg)/share/data/README"
{platform: {binfmt: elf, launch: "/unused/launch"}} | to json | save $"($t)/attrs.json"
$env.NIX_ATTRS_JSON_FILE = $"($t)/attrs.json"
$env.NIX_STORE = $t

# every file and link under a tree with what it holds or points at
def snapshot [root: string]: nothing -> list<string> {
  ^find $root | lines | sort | each {|f|
    let kind = ($f | path type)
    let what = match $kind { file => (open --raw $f), symlink => (^readlink $f), _ => "" }
    $"($f | path relative-to $root) ($kind) ($what)"
  }
}

$env.out = $inner
wrap $pkg [] {} {"inner.conf": "inner\n", "shared.conf": "old\n"} thing
let before = (snapshot $inner)

$env.out = $outer
wrap $inner [] {} {"outer.conf": "outer\n", "shared.conf": "new\n"} thing

let after = (snapshot $inner)
assert $"the inner tree is unchanged: ($after | where { $in not-in $before })" ($after == $before)
let dir = $"($outer)/share/wrap/thing"
assert "outer share/wrap/<pname> is a real directory" (($dir | path type) == dir)
assert "outer share/wrap is a real directory" (($"($outer)/share/wrap" | path type) == dir)
assert "outer inherits the inner-only file" ((open --raw $"($dir)/inner.conf") == "inner\n")
assert "outer has its own file" ((open --raw $"($dir)/outer.conf") == "outer\n")
assert "outer replaces the shared file" ((open --raw $"($dir)/shared.conf") == "new\n")
assert "the replaced file is a real file, not a link" (($"($dir)/shared.conf" | path type) == file)
assert "the package's share/data is still reachable" ((open --raw $"($outer)/share/data/README") == "docs\n")
let abs = (^find $outer -lname '/*' | lines)
assert $"no absolute symlink in the outer tree: ($abs)" ($abs | is-empty)

$env.out = $real_out
done
