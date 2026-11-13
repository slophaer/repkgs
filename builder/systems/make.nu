use ../core.nu *
use ../prefix.nu

# plain Makefile projects: make [targets] flags, in the source tree, after the project's
# hand-written `make.configureScript` when it has one. autotools.nu builds on this

export const OPTIONS = {
  flags: {default: [], doc: "arguments for every make invocation (build, test, install)"}
  configureScript: {default: configure, doc: "hand-written configure script relative to the project, run with --prefix when it exists"}
  configureFlags: {default: [], doc: "extra arguments for make.configureScript"}
  programs: {default: [], doc: "programs the Makefile names without the platform's executable suffix (cc writes lua.exe, `make install` copies lua)"}
  installFlags: {default: [], doc: "arguments for `make install` only"}
  buildTarget: {default: [], doc: "make goals for build (empty: the makefile's default goal)"}
  testTarget: {default: [check], doc: "make goals for test"}
  installTarget: {default: [install], doc: "make goals for install"}
}

export def --env setup []: nothing -> nothing {
  let sh = (if (which bash | is-not-empty) { tool bash } else { tool sh })
  load-env {CONFIG_SHELL: $sh, SHELL: $sh}
}

export def workdir []: nothing -> string { project-dir make }

# the install prefix: a declared spec.prefix, or the scratch output. A declared one is the only
# one: a raw PREFIX=/prefix= or --prefix would configure or install elsewhere. Without one, raw
# flags stay the package's business (those that install by hand)
def install-prefix []: nothing -> string {
  let o = (options make)
  if (ctx).spec.prefix? != null {
    prefix check-flags ($o.flags ++ $o.installFlags) '^(PREFIX|prefix)=' prefix
    prefix check-flags $o.configureFlags '^--prefix($|=)' prefix
  }
  prefix resolve
}

# #!/bin/sh would be the sandbox's. MAKEFLAGS for scripts that compile (cmake's bootstrap)
export def configure []: nothing -> nothing {
  let c = (ctx); let o = (options make)
  let prefix = (install-prefix)
  let script = $"./($o.configureScript)"
  if not ($script | path exists) { return }
  let argv = (if (open --raw $script | lines | first) =~ '^#! ?/bin/sh' { [$env.CONFIG_SHELL $script] } else { [$script] })
  with-env {MAKEFLAGS: $"-j($c.njobs)"} { x ($argv | first) ...($argv | skip 1) $"--prefix=($prefix)" ...$o.configureFlags }
}

export def run-build [flags: list<string>, targets: list<string>]: nothing -> nothing { x make $"-j((ctx).njobs)" ...$targets ...$flags }

# VERBOSE: automake prints test-suite.log on failure
export def run-test [flags: list<string>, targets: list<string>]: nothing -> nothing { x make $"-j(test-jobs)" VERBOSE=1 ...$targets ...$flags }

export def run-install [flags: list<string>, targets: list<string>]: nothing -> nothing { x make ...$targets ...$flags }

# `make.programs` around an install step: the suffix-less name exists for the Makefile before,
# the installed copy gets its suffix back after
def with-programs [programs: list<string>, install: closure]: nothing -> nothing {
  let c = (ctx)
  let exe = $c.platform.ext.exe
  if $exe == "" { do $install; return }
  for f in ($programs | each {|p| files $"**/($p)($exe)" } | flatten) { ^cp $f ($f | str replace -r $'\($exe)$' "") }
  do $install
  for f in ($programs | each {|p| $"($c.out)/bin/($p)" } | where { $in | path exists }) { ^mv $f $"($f)($exe)" }
}

# For hand-written Makefiles, on every target: PREFIX/prefix, because some compile the prefix in
# before `install` (Darwin install names), and UNAME, because they choose flags by
# `UNAME := $(shell uname)` (xxhash, giflib, zstd, lz4), which must describe the target when cross
# compiling. Placed first so make.flags can override both
def flags []: nothing -> list<string> {
  let c = (ctx)
  let prefix = (install-prefix)
  [$"PREFIX=($prefix)" $"prefix=($prefix)"] ++ (if $c.platform.cross { [$"UNAME=($c.platform.osNames.uname)"] } else { [] }) ++ (options make).flags
}

export def build []: nothing -> nothing { run-build (flags) (options make).buildTarget }
export def test []: nothing -> nothing { run-test (flags) (options make).testTarget }
# With spec.prefix, install via DESTDIR (also on the command line: a Makefile may assign it) and
# copy the prefix subtree to $out
export def install []: nothing -> nothing {
  let o = (options make)
  let prefix = (install-prefix)
  with-programs $o.programs {
    prefix install $prefix {
      let destdir = (if $prefix != (ctx).out { [$"DESTDIR=($env.DESTDIR)"] } else { [] })
      run-install ((flags) ++ $o.installFlags ++ $destdir) $o.installTarget
    }
  }
}
