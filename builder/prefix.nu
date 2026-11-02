# Shared staged install for a declared image prefix, rather than the scratch output.
use core.nu *

# Build-system defs override the common prefix, as they do for other defaults.
export def resolve [override?: string]: nothing -> string {
  let prefix = ($override | default ((ctx).spec.prefix? | default (ctx).out))
  if not ($prefix | str starts-with /) or ".." in ($prefix | path split) {
    error make {msg: "prefix must be absolute, without parent-directory components"}
  }
  $prefix
}

# Opaque flags must not silently select a prefix the install phase cannot see.
export def check-flags [flags: list<string>, pattern: string, setting: string]: nothing -> nothing {
  if ($flags | any { $in =~ $pattern }) {
    error make {msg: $"configure prefix flags are unsupported; set ($setting) instead"}
  }
}

export def install [prefix: string, run: closure]: nothing -> nothing {
  let c = (ctx)
  if $prefix == $c.out { do $run; return }
  let destdir = $"($c.build)/dest"
  with-env {DESTDIR: $destdir} { do $run }
  let subtree = ($prefix | str trim --left --char '/')
  let root = ($destdir | path join $subtree | path expand -n | str trim --right --char '/')
  if ($root | path type) != dir { error make {msg: $"declared prefix is not a staged directory: ($prefix)"} }
  let outside = (^find $destdir ! -type d -print0 | split row (char nul)
    | where { $in != '' and $in != $root and not ($in | str starts-with $"($root)/") })
  if ($outside | is-not-empty) {
    error make {msg: $"files outside the declared prefix ($prefix): ($outside | str join ', '). Use a package-local install phase to keep other roots."}
  }
  ^cp -r $"($root)/." $c.out
  # .pc files can live in share/, lib64/ or multiarch lib directories, not just lib/pkgconfig.
  for f in (files $"($c.out)/**/*.pc") {
    let up = ($f | path dirname | path relative-to $c.out | path split | each { '..' } | str join '/')
    edit $f {
      lines | each {|line|
        if $line == $"prefix=($prefix)" { 'prefix=${pcfiledir}/' + $up } else { $line }
      } | str join "\n" | $"($in)\n"
    }
  }
}
