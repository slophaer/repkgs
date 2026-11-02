# .note.dlopen: a soname a binary only dlopen()s is found through its RUNPATH, with no
# LD_LIBRARY_PATH, from the store and from a moved copy of the closure
use checks.nu *
use finish.nu [dlopen-check inventory]

let real = $"($env.pkg)/bin/.dlz"
let bin = (if ($real | path exists) { $real } else { $"($env.pkg)/bin/dlz" })
let rpath = (^llvm-readelf -d $bin | lines | where { $in =~ RUNPATH } | str join "\n")
assert $"RUNPATH names zlib: ($rpath)" ($rpath =~ 'zlib/lib')
assert $"RUNPATH is relative: ($rpath)" (not ($rpath =~ '\[/nix/store'))
let out = (^env -i $"($env.pkg)/bin/dlz" | complete)
assert $"dlopen finds libz in place: ($out.stdout)($out.stderr)" ($out.exit_code == 0 and ($out.stdout | str starts-with "zlib "))

# moved: the package and its dependencies under another root, siblings as in the store
let t = $"($env.TMPDIR? | default /tmp)/dlopen-test/store"
mkdir $t
for p in (ls /nix/store | where type == dir | get name | where { $in =~ '-(test-dlopen|zlib|glibc-[^/]*|launch-[^/]*)$' }) {
  ^cp -a $p $t
}
let moved = $"($t)/($env.pkg | path basename)/bin/dlz"
let out = (^env -i $moved | complete)
assert $"dlopen finds libz from a moved closure: ($out.stdout)($out.stderr)" ($out.exit_code == 0 and ($out.stdout | str starts-with "zlib "))

# the package's own shipped library: found through the $ORIGIN-relative RUNPATH
let selfbin = (if ($"($env.pkg)/bin/.dlself" | path exists) { $"($env.pkg)/bin/.dlself" } else { $"($env.pkg)/bin/dlself" })
let self = (^env -i $selfbin | complete)
assert $"dlopen finds the package's own library: ($self.stdout)($self.stderr)" ($self.exit_code == 0 and ($self.stdout | str starts-with "self 42"))
# ... and it is part of the availability check: a copy whose $ORIGIN/../lib holds no libself.so.1
# must fail, because the package's own lib/ does have it (before, it was "in no dependency")
let root = $"($env.TMPDIR? | default /tmp)/dlopen-own"
mkdir $"($root)/bin"
^cp $selfbin $"($root)/bin/dlself"
let c = {
  out: $env.pkg
  dest: $root
  deps: []
  platform: {binfmt: "elf"}
  spec: {}
}
fails "own library not on RUNPATH is an error" { dlopen-check $c (inventory $root) }
done
