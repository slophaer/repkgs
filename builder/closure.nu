# closure: create a tarball of a closure with a bin/ profile.
# The tarball holds:
#   nix/store/<hash>-* for every runtime path of the roots
#   bin/ with relative symlinks to the roots' launchers
# On any Linux host: tar x && PATH=$PWD/bin:$PATH runs the tools.

use core.nu *

# Read the closure from exportReferencesGraph
def read-closure []: nothing -> list<string> {
  let attrs = (open $env.NIX_ATTRS_JSON_FILE)
  # The closure is in attrs.closure as a list of { path, ... } records
  $attrs.closure | get path
}

# Create relative symlink from bin/<name> to the store binary
def relative-link [from: string, to: string]: nothing -> string {
  # from: /build/out/bin/<name>
  # to: /nix/store/<hash>-pkg/bin/<name>
  # result: ../nix/store/<hash>-pkg/bin/<name>
  let from_parts = ($from | path split)
  let to_parts = ($to | path split)
  # Count common prefix
  let common = ($from_parts | zip $to_parts | take while { $in.0 == $in.1 } | length)
  let up = ($from_parts | skip $common | drop 1 | each { ".." })
  let down = ($to_parts | skip $common)
  $up ++ $down | path join
}

# Main entry point
export def main [roots: list<string>, name: string]: nothing -> nothing {
  let out = $env.out
  let closure = (read-closure)

  print -e $"closure: ($closure | length) paths in closure"

  # Create a temporary build directory
  let build = $"($env.NIX_BUILD_TOP)/closure-build"
  mkdir $build
  let store_dir = $"($build)/nix/store"
  mkdir $store_dir

  # Copy all closure paths
  for p in $closure {
    let basename = ($p | path basename)
    print -e $"closure: copying ($basename)"
    ^cp -a $p $"($store_dir)/($basename)"
  }

  # Make everything writable so tar can read it
  ^chmod -R u+w $build

  # Create bin/ with symlinks to roots' launchers
  mkdir $"($build)/bin"
  for root in $roots {
    let bindir = $"($root)/bin"
    if not ($bindir | path exists) {
      continue
    }

    # Find all launchers (files or symlinks in bin/, not hidden)
    for f in (ls $bindir | get name | where { ($in | path basename) !~ '^\.' }) {
      let bname = ($f | path basename)
      let dest = $"($build)/bin/($bname)"

      if ($dest | path exists) {
        continue  # skip duplicates
      }

      # Create relative symlink to the store copy
      let rel_root = ($root | path basename)
      let target = $"../nix/store/($rel_root)/bin/($bname)"
      ^ln -sf $target $dest

      print -e $"closure: bin/($bname) -> ($target)"
    }
  }

  # Create the tarball
  mkdir $out
  cd $build
  ^tar -cf $"($out)/($name).tar" nix bin

  print -e $"closure: ($name).tar created"
}
