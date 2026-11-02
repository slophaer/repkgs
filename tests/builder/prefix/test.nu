use core.nu *
use checks.nu done
use systems/autotools.nu
use systems/meson.nu
use systems/cmake.nu

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
for backend in [autotools meson cmake] {
  for case in [
    {name: default, prefix: null, override: null}
    {name: usr, prefix: /usr, override: null}
    {name: root, prefix: /, override: null}
    {name: override, prefix: /usr, override: /opt/custom}
    {name: builder-only, prefix: null, override: /opt/custom}
    {name: raw-flag, prefix: null, override: null}
    {name: raw-split, prefix: null, override: null}
    {name: raw-alias, prefix: null, override: null}
  ] {
    if $backend == autotools and $case.override != null { continue }
    if $case.name == raw-alias and $backend != cmake { continue }
    let dir = $"($root)/($backend)-($case.name)"
    mkdir $"($dir)/source" $"($dir)/build" $"($dir)/out"
    $body | save $"($dir)/source/configure"
    "# fixture" | save $"($dir)/source/CMakeLists.txt"
    let defs = if $case.override == null { {} } else if $backend == meson { {prefix: $case.override} } else { {CMAKE_INSTALL_PREFIX: $case.override} }
    let opts = match $backend {
      autotools => (merge-options autotools $autotools.OPTIONS {})
      meson => (merge-options meson $meson.OPTIONS {defs: $defs})
      cmake => (merge-options cmake $cmake.OPTIONS {defs: $defs})
    }
    let flags = if $case.name == raw-split {
      match $backend {
        cmake => ['-D' 'CMAKE_INSTALL_PREFIX:PATH=/opt/raw']
        meson => ['-D' 'prefix=/opt/raw']
        autotools => ['prefix=/opt/raw']
      }
    } else if $case.name == raw-alias { ['--install-prefix=/opt/raw'] } else {
      [(if $backend == cmake { '-DCMAKE_INSTALL_PREFIX=/opt/raw' } else { '--prefix=/opt/raw' })]
    }
    let options = if ($case.name | str starts-with raw-) { $opts | upsert flags $flags } else { $opts }
    let spec = ({$backend: ($options | merge {root: "."})} | merge (if $case.prefix == null { {} } else { {prefix: $case.prefix} }))
    $env.TEST_OUT = $"($dir)/out"
    $env.PKGS_CTX = {
      spec: $spec, out: $env.TEST_OUT, dest: $env.TEST_OUT, deps: [], roots: [], njobs: 1,
      src: $"($dir)/source", build: $"($dir)/build",
      platform: {cross: false, os: linux, posix: true, sysroot: /unused, emulator: []},
      testsRun: false, cache: false
    }
    cd $"($dir)/build"
    let result = (try {
      match $backend {
        autotools => { autotools configure }
        meson => { meson configure }
        cmake => { cmake configure }
      }
      {ok: true, message: ''}
    } catch {|e| {ok: false, message: $e.msg} })
    if ($case.name | str starts-with raw-) {
      if $result.ok or not ($result.message | str contains 'prefix flags') { error make {msg: $"($backend): opaque prefix flag was accepted"} }
      print $"ok: ($backend) raw prefix flag rejected"
      continue
    }
    if not $result.ok { error make {msg: $result.message} }
    match $backend {
      autotools => { autotools install }
      meson => { meson install }
      cmake => { cmake install }
    }
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
}
cd $pwd
rm -rf $root
done
