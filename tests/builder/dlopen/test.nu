# .note.dlopen: a soname a binary only dlopen()s is found through its RUNPATH, with no
# LD_LIBRARY_PATH
use checks.nu *
use finish.nu [dlopen-check inventory]

let real = $"($env.pkg)/bin/.dlz"
let bin = (if ($real | path exists) { $real } else { $"($env.pkg)/bin/dlz" })
let rpath = (^llvm-readelf -d $bin | lines | where { $in =~ RUNPATH } | str join "\n")
assert $"RUNPATH names zlib: ($rpath)" ($rpath =~ 'zlib/lib')
assert $"RUNPATH is relative: ($rpath)" (not ($rpath =~ '\[/nix/store'))
let out = (^env -i $"($env.pkg)/bin/dlz" | complete)
assert $"dlopen finds libz in place: ($out.stdout)($out.stderr)" ($out.exit_code == 0 and ($out.stdout | str starts-with "zlib "))

# the package's own shipped library: found through the $ORIGIN-relative RUNPATH
let selfbin = (if ($"($env.pkg)/bin/.dlself" | path exists) { $"($env.pkg)/bin/.dlself" } else { $"($env.pkg)/bin/dlself" })
let self = (^env -i $selfbin | complete)
assert $"dlopen finds the package's own library: ($self.stdout)($self.stderr)" ($self.exit_code == 0 and ($self.stdout | str starts-with "self 42"))
# A bad own-library RUNPATH must fail. Moving the file alone does not do this: the checker maps
# dest back to out. Replace lib with bad without changing the ELF string table's offsets.
let root = $"($env.TMPDIR? | default /tmp)/dlopen-own"
mkdir $"($root)/bin"
^cp $selfbin $"($root)/bin/dlself"
let raw = (open --raw $"($root)/bin/dlself" | into binary)
let broken = ($raw | bytes replace --all ('$ORIGIN/../lib' | into binary) ('$ORIGIN/../bad' | into binary))
assert "the own-library RUNPATH probe changed" ($raw != $broken)
chmod u+w $"($root)/bin/dlself"
$broken | save -f $"($root)/bin/dlself"
let c = {
  out: $env.pkg
  dest: $root
  deps: []
  platform: {binfmt: "elf"}
  spec: {}
}
let message = (try { dlopen-check $c (inventory $root); "" } catch {|e| $e.msg })
assert "own library not on RUNPATH is the reported error" ($message | str contains 'bin/dlself: libself.so.1')
done
