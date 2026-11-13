use core.nu *
use checks.nu done
use systems/autotools.nu
use systems/meson.nu
use systems/cmake.nu
use systems/make.nu

let pwd = $env.PWD
let root = (mktemp -d -t prefix.XXXXXX)
let shell = (which sh | first | get path)
let body = (open --raw ($env.fixtures | path join tool.sh))
mkdir $"($root)/bin"
for name in [meson cmake make jig] {
  $"#!($shell)\n($body)" | save $"($root)/bin/($name)"
  ^chmod +x $"($root)/bin/($name)"
}
$env.PATH = [$"($root)/bin"] ++ $env.PATH
$env.CONFIG_SHELL = $shell
$env.PKGS_CC = "{}"
def configure-with [backend: string] {
  match $backend {
    autotools => { autotools configure }
    meson => { meson configure }
    cmake => { cmake configure }
    make => { make configure }
  }
}

def install-with [backend: string] {
  match $backend {
    autotools => { autotools install }
    meson => { meson install }
    cmake => { cmake install }
    make => { make install }
  }
}

# the error install-with raises, '' when it succeeds
def install-error [backend: string]: nothing -> string {
  try { install-with $backend; '' } catch {|e| $e.msg }
}

for backend in [autotools meson cmake make] {
  for case in [
    {name: default, prefix: null, override: null}
    {name: usr, prefix: /usr, override: null}
    {name: root, prefix: /, override: null}
    {name: override, prefix: /usr, override: /opt/custom}
    {name: builder-only, prefix: null, override: /opt/custom}
    {name: bad-relative, prefix: usr, override: null}
    {name: bad-parent, prefix: /usr/../../tmp, override: null}
    {name: bad-def, prefix: /usr, override: relative}
    # before the other raw- cases: the last case's spec stays for the checks after the loop
    {name: raw-configure, prefix: /usr, override: null}
    {name: raw-make, prefix: /usr, override: null}
    {name: raw-install, prefix: /usr, override: null}
    {name: raw-flag, prefix: null, override: null}
    {name: raw-split, prefix: null, override: null}
    {name: raw-alias, prefix: null, override: null}
    {name: raw-abbrev, prefix: null, override: null}
  ] {
    if $backend in [autotools make] and $case.override != null { continue }
    if $case.name == raw-alias and $backend == meson { continue }
    if $case.name in [raw-abbrev raw-make raw-install] and $backend not-in [autotools make] { continue }
    if $case.name == raw-configure and $backend != make { continue }
    # make rejects prefix flags only when a prefix is declared: these have none
    if $case.name in [raw-flag raw-split raw-alias raw-abbrev] and $backend == make { continue }
    let dir = $"($root)/($backend)-($case.name)"
    mkdir $"($dir)/source" $"($dir)/build" $"($dir)/out"
    # make runs a hand-written configure through CONFIG_SHELL only when it says #!/bin/sh
    $"#!/bin/sh\n($body)" | save $"($dir)/source/configure"
    "# fixture" | save $"($dir)/source/CMakeLists.txt"
    let defs = if $case.override == null { {} } else if $backend == meson { {prefix: $case.override} } else { {CMAKE_INSTALL_PREFIX: $case.override} }
    let opts = match $backend {
      autotools => (merge-options autotools $autotools.OPTIONS {})
      meson => (merge-options meson $meson.OPTIONS {defs: $defs})
      cmake => (merge-options cmake $cmake.OPTIONS {defs: $defs})
      make => (merge-options make $make.OPTIONS {})
    }
    let flags = if $case.name == raw-split {
      match $backend {
        cmake => ['-D' 'CMAKE_INSTALL_PREFIX:PATH=/opt/raw']
        meson => ['-D' 'prefix=/opt/raw']
        autotools => ['prefix=/opt/raw']
      }
    } else if $case.name == raw-alias {
      [(if $backend == autotools { '-prefix=/opt/raw' } else { '--install-prefix=/opt/raw' })]
    } else if $case.name == raw-abbrev { ['--pref=/opt/raw'] } else {
      [(if $backend == cmake { '-DCMAKE_INSTALL_PREFIX=/opt/raw' } else { '--prefix=/opt/raw' })]
    }
    # make's prefix= overrides the configured one at install
    # autotools' make variable is prefix, hand-written Makefiles mostly use PREFIX
    let options = if $case.name == raw-make and $backend == make { $opts | upsert flags ['PREFIX=/opt/raw'] } else if $case.name == raw-make {
      $opts | upsert makeFlags ['prefix=/opt/raw']
    } else if $case.name == raw-configure {
      $opts | upsert configureFlags ['--prefix=/opt/raw']
    } else if $case.name == raw-install {
      $opts | upsert installFlags ['prefix=/opt/raw']
    } else if ($case.name | str starts-with raw-) { $opts | upsert flags $flags } else { $opts }
    let spec = ({$backend: ($options | merge {root: "."})} | merge (if $case.prefix == null { {} } else { {prefix: $case.prefix} }))
    $env.TEST_OUT = $"($dir)/out"
    $env.PKGS_CTX = {
      spec: $spec, out: $env.TEST_OUT, dest: $env.TEST_OUT, deps: [], roots: [], njobs: 1,
      src: $"($dir)/source", build: $"($dir)/build",
      platform: {cross: false, os: linux, posix: true, sysroot: /unused, emulator: [], ext: {exe: ''}},
      testsRun: false, cache: false
    }
    # make configures and builds in the source tree
    cd (if $backend == make { $"($dir)/source" } else { $"($dir)/build" })
    let result = (try {
      configure-with $backend
      {ok: true, message: ''}
    } catch {|e| {ok: false, message: $e.msg} })
    if ($case.name | str starts-with bad-) {
      if $result.ok or not ($result.message | str contains 'prefix must') { error make {msg: $"($backend): invalid prefix was accepted"} }
      print $"ok: ($backend) invalid prefix rejected"
      continue
    }
    if ($case.name | str starts-with raw-) {
      if $result.ok or not ($result.message | str contains 'prefix flags') { error make {msg: $"($backend): opaque prefix flag was accepted"} }
      print $"ok: ($backend) raw prefix flag rejected"
      continue
    }
    if not $result.ok { error make {msg: $result.message} }
    install-with $backend
    let want = ($case.override | default ($case.prefix | default $env.TEST_OUT))
    let configured = (open --raw configured-prefix | str trim)
    if $configured != $want { error make {msg: $"($backend) ($case.name): configured ($configured), wanted ($want)"} }
    for sub in [lib/pkgconfig share/pkgconfig lib/triple/pkgconfig] {
      let file = $"($env.TEST_OUT)/($sub)/fixture.pc"
      let up = ($sub | path split | each { '..' } | str join '/')
      let expected = if $want == $env.TEST_OUT { $"prefix=($want)" } else { 'prefix=${pcfiledir}/' + $up }
      if (open --raw $file | lines | first) != $expected {
        error make {msg: $"($backend) ($case.name): ($sub) has the wrong pkg-config prefix"}
      }
    }
    print $"ok: ($backend) ($case.name)"
  }
  if $backend in [autotools cmake] {
    $env.CACHE_KEYS = $"($root)/($backend)-keys"
    $env.PKGS_CTX = ($env.PKGS_CTX | upsert cache true | update spec { update $backend { upsert flags [] } })
    for prefix in [/usr /opt/cache-change] {
      $env.PKGS_CTX = ($env.PKGS_CTX | upsert spec.prefix $prefix)
      if ('install' | path exists) { rm install }
      match $backend {
        autotools => { autotools configure }
        cmake => { cmake configure }
      }
    }
    if (open --raw $env.CACHE_KEYS | lines | uniq | length) != 2 {
      error make {msg: $"($backend): prefix change reused the configure cache key"}
    }
    print $"ok: ($backend) prefix is in the configure cache key"
  }
  $env.PKGS_CTX = ($env.PKGS_CTX | upsert cache false | update spec { upsert prefix /usr | update $backend { upsert flags [] | upsert makeFlags [] | upsert installFlags [] | upsert configureFlags [] } })
  if ('install' | path exists) { rm install }
  configure-with $backend
  let outside = (with-env {OUTSIDE_PREFIX: '1'} { install-error $backend })
  if not ($outside | str contains 'outside the declared prefix') { error make {msg: $"($backend): files outside the declared prefix disappeared"} }
  print $"ok: ($backend) rejects files outside the declared prefix"

  # stagedRoots: a root goes to its output directory or, as null, away; a nested root first
  $env.PKGS_CTX = ($env.PKGS_CTX | upsert spec.stagedRoots {"/etc": share/factory/etc, "/etc/ssh": share/ssh, "/var": null})
  with-env {OUTSIDE_PREFIX: '1', STAGED: '1'} { install-with $backend }
  let out = $env.TEST_OUT
  if not ($"($out)/share/factory/etc/unexpected" | path exists) { error make {msg: $"($backend): /etc is not in share/factory/etc"} }
  if not ($"($out)/share/ssh/sshd_config" | path exists) or ($"($out)/share/factory/etc/ssh" | path exists) {
    error make {msg: $"($backend): the nested root /etc/ssh is not only in share/ssh"}
  }
  if (^find $out -name state | str trim) != '' { error make {msg: $"($backend): the dropped root /var was kept"} }
  print $"ok: ($backend) keeps and drops staged roots"

  for bad in [{"etc": x} {"/etc": /abs} {"/etc": ../up} {"/etc": ''} {"/usr/share": x} {"/": x} {"/var/../usr": x}] {
    $env.PKGS_CTX = ($env.PKGS_CTX | upsert spec.stagedRoots $bad)
    if not (install-error $backend | str contains 'stagedRoots') { error make {msg: $"($backend): bad stagedRoots ($bad | to nuon) accepted"} }
  }
  print $"ok: ($backend) rejects bad staged roots"
  # nothing to stage into without a declared prefix: the install goes straight to the output
  $env.PKGS_CTX = ($env.PKGS_CTX | upsert spec.stagedRoots {"/etc": x} | update spec { reject prefix })
  if not (install-error $backend | str contains 'stagedRoots') { error make {msg: $"($backend): stagedRoots without a prefix accepted"} }
  print $"ok: ($backend) stagedRoots needs a prefix"
  $env.PKGS_CTX = ($env.PKGS_CTX | update spec { reject stagedRoots })
}

# make without a declared prefix still takes a raw PREFIX= (packages that install by hand)
let dir = $"($root)/make-raw-undeclared"
mkdir $"($dir)/source" $"($dir)/build" $"($dir)/out"
$"#!/bin/sh\n($body)" | save $"($dir)/source/configure"
$env.PKGS_CTX = ($env.PKGS_CTX | update spec { {make: ($in.make | upsert flags ['PREFIX=/opt/raw'] | upsert configureFlags ['--prefix=/opt/raw'])} } | update src $"($dir)/source" | update build $"($dir)/build")
cd $"($dir)/source"
make configure
if (open --raw configured-prefix | str trim) != /opt/raw { error make {msg: "make: an undeclared prefix lost the raw --prefix"} }
print "ok: make takes raw prefix flags when no prefix is declared"
cd $pwd
rm -rf $root
done
