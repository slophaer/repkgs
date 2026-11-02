# closure: create a tarball of a closure with a bin/ profile.
# The tarball holds:
#   nix/store/<hash>-* for every runtime path of the roots
#   bin/ with relative symlinks to the roots' launchers
# On any Linux host: tar x && PATH=$PWD/bin:$PATH runs the tools.
# The archive is reproducible: entries sorted by name, owner 0/0, one fixed mtime.

use core.nu *

# Main entry point
export def main [roots: list<string>, name: string]: nothing -> nothing {
  let out = $env.out
  let closure = (open $env.NIX_ATTRS_JSON_FILE | get closure.path)

  print -e $"closure: ($closure | length) paths in closure"

  let build = $"($env.NIX_BUILD_TOP)/closure-build"
  let store_dir = $"($build)/nix/store"
  mkdir $store_dir

  # -RP, not -a or -d: no hard links, so the archive does not depend on store optimisation
  for p in $closure {
    ^cp -RP $p $"($store_dir)/($p | path basename)"
  }

  # bin/: relative symlinks to the roots' launchers. A name two roots install is an error
  mkdir $"($build)/bin"
  for root in ($roots | uniq) {
    let bindir = $"($root)/bin"
    if not ($bindir | path exists) { continue }
    for f in (ls $bindir | get name | where { ($in | path basename) !~ '^\.' }) {
      let bname = ($f | path basename)
      let dest = $"($build)/bin/($bname)"
      if ($dest | path type) != null {
        error make {msg: $"closure: bin/($bname) is in two roots: (^readlink $dest) and ($root)"}
      }
      let target = $"../nix/store/($root | path basename)/bin/($bname)"
      ^ln -s $target $dest
      print -e $"closure: bin/($bname) -> ($target)"
    }
  }

  mkdir $out
  cd $build
  # u+w: store directories are read-only, and a tar that applies a directory's mode before its
  # contents could not extract them
  ^tar -cf $"($out)/($name).tar" --sort --mtime @1 --owner root:0 --group root:0 --numeric-owner --mode u+w bin nix

  print -e $"closure: ($name).tar created"
}
