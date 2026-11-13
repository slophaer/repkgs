# Shared staged install for a declared prefix (spec.prefix), rather than the scratch output.
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
    error make {msg: $"prefix flags are unsupported; set ($setting) instead"}
  }
}

# spec.stagedRoots: what the install puts outside the prefix that the package keeps or drops,
# {"/etc": "share/factory/etc", "/var": null}: a root's subtree goes to that directory of the
# output, or away for null. Longest root first, so "/etc/ssh" is taken before "/etc"
def staged-roots [prefix: string]: nothing -> list<record<root: string, to: any>> {
  let p = ($prefix | str trim --right --char '/')
  mut roots = []
  # a loop, not `items`: an error inside a closure would lose its message
  for e in ((ctx).spec.stagedRoots? | default {} | transpose root to) {
    let r = ($e.root | str trim --right --char '/')
    if not ($e.root | str starts-with /) or ".." in ($e.root | path split) or $r == "" {
      error make {msg: $"stagedRoots: ($e.root) must be an absolute directory other than /, without .."}
    }
    if $p == "" or $r == $p or ($r | str starts-with $"($p)/") or ($p | str starts-with $"($r)/") {
      error make {msg: $"stagedRoots: ($e.root) overlaps the prefix ($prefix)"}
    }
    let to = $e.to
    if $to != null and (($to | describe) != string or $to == "" or ($to | str starts-with /) or ".." in ($to | path split)) {
      error make {msg: $"stagedRoots: ($e.root) must map to a relative directory of the output without .., or to null"}
    }
    $roots ++= [{root: $r, to: $to}]
  }
  $roots | sort-by --reverse { $in.root | str length }
}

export def install [prefix: string, run: closure]: nothing -> nothing {
  let c = (ctx)
  if $prefix == $c.out {
    if ($c.spec.stagedRoots? | default {} | is-not-empty) {
      error make {msg: "stagedRoots needs a declared prefix: without one the install goes straight to the output"}
    }
    do $run
    return
  }
  let roots = (staged-roots $prefix)
  let destdir = $"($c.build)/dest"
  with-env {DESTDIR: $destdir} { do $run }
  let subtree = ($prefix | str trim --left --char '/')
  let root = ($destdir | path join $subtree | path expand -n | str trim --right --char '/')
  if ($root | path type) != dir { error make {msg: $"declared prefix is not a staged directory: ($prefix)"} }
  for r in $roots {
    let staged = $"($destdir)($r.root)"
    if not ($staged | path exists -n) { continue }
    if $r.to == null {
      note staged-root $"($r.root): dropped"
    } else {
      let to = $"($c.out)/($r.to)"
      mkdir ($to | path dirname)
      if ($staged | path type) == dir { mkdir $to; ^cp -r $"($staged)/." $to } else { ^cp -P $staged $to }
      note staged-root $"($r.root) -> ($r.to)"
    }
    ^rm -rf $staged
  }
  let outside = (^find $destdir ! -type d -print0 | split row (char nul)
    | where { $in != '' and $in != $root and not ($in | str starts-with $"($root)/") })
  if ($outside | is-not-empty) {
    error make {msg: $"files outside the declared prefix ($prefix): ($outside | str join ', '). Declare their roots in stagedRoots, or use a package-local install phase."}
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
