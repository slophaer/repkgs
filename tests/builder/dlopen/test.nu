# .note.dlopen: the soname a binary only dlopen()s is found through its RUNPATH, with no
# LD_LIBRARY_PATH, from the store and from a moved copy of the closure
use checks.nu *

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
done
