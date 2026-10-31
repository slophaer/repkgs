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
    # The CA store deduplicates identical files via hardlinks, so a file in glibc
    # (e.g., libunwind.so.1) may share an inode with one in runtimes. cp -s refuses
    # to replace a symlink when source and destination resolve to the same inode,
    # printing "'file' is 'path'". Ignore errors for files that already exist with
    # identical content; fail on other errors.
    let r = (^cp -rsf $"($p)/." $"($out)/" | complete)
    if $r.exit_code != 0 {
      # Each "'name' is 'path'" line is a hardlink conflict; other errors are fatal
      let lines = ($r.stderr | lines)
      let fatal = ($lines | where {|l| not ($l =~ "^cp: '.+' is '/") })
      if ($fatal | is-not-empty) {
        print -e ($lines | str join "\n")
        error make {msg: $"cp failed with exit code ($r.exit_code)"}
      }
    }
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
