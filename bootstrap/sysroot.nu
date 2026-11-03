# What `clang --sysroot` / `-isysroot` expects: {usr/,}include, {usr/,}lib{,64}, and our
# compiler-rt as the resource dir under lib/clang. $env.parts (libc, linux-headers, runtimes, an
# SDK) are merged as symlink trees, later parts win (musl and the kernel both ship include/scsi).
use lib.nu *

# `cp -s` writes absolute targets. The store path is rewritten when the output is added, but a closure
# copied elsewhere must still resolve: make every link point to its target relative to its own directory
def relativize-links [out: path]: nothing -> nothing {
  for l in (^find $out -type l | lines | sort) {
    let target = (^readlink $l | str trim)
    if not ($target | str starts-with "/") { continue }
    let from = ($l | path dirname | path split)
    let to = ($target | path split)
    let n = ($from | zip $to | take while {|p| $p.0 == $p.1 } | length)
    let rel = ([...(0..<(($from | length) - $n) | each { ".." }) ...($to | skip $n)] | str join "/")
    x ln -sfn $rel $l
  }
}

def main []: nothing -> nothing {
  let out = $env.out
  mkdir $"($out)/include" $"($out)/lib"
  for p in ($env.parts | split row " ") {
    # Remove old links first: cp -s rejects same-inode replacements after store optimisation.
    mut replace = []
    for f in (^find $p -mindepth 1 -print0 | split row (char nul) | where { $in != "" }) {
      let dest = ($out | path join ($f | path relative-to $p))
      if ($f | path type) == dir {
        # Never remove files through a directory link into an input.
        if ($dest | path type) == symlink { error make {msg: $"sysroot directory conflicts with a link: ($dest)"} }
      } else if ($dest | path type) == symlink {
        $replace ++= [$dest]
      }
    }
    if ($replace | is-not-empty) { x rm -f -- ...$replace }
    let r = (^cp -rsf $"($p)/." $"($out)/" | complete)
    if $r.exit_code != 0 { error make {msg: $r.stderr} }
  }
  x cp -rs $env.resource $"($out)/lib/clang"
  relativize-links $out
  # MacOSX.sdk brings a real usr/ (and the SDKSettings.json the darwin driver reads), ELF sysroots alias it
  if not ($"($out)/usr" | path exists) { x ln -s . $"($out)/usr" }
  x ln -s lib $"($out)/lib64"
  # tools copy `cc -print-file-name=crt*.o` verbatim (rust's self-contained/): no symlinks
  for o in (files $"($out)/lib/*crt*.o") { let t = ($o | path expand); rm $o; cp $t $o }
  # depfiles name the symlink targets. The compile cache needs to know them (lib.nu JIG_STORE_ROOTS)
  $"($env.parts) ($env.resource)\n" | save $"($out)/roots"
}
