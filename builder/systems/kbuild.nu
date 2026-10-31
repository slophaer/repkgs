# Linux kernel kbuild system: defconfig + merged fragment + olddefconfig + verification, then
# make with LLVM=1 LLVM_IAS=1. The kernel sets its own hardening (stack protector, CFI), so
# jig's injected flags must not reach it. Packages pass CC/LD/AR/... pointing at the unwrapped
# toolchain to keep jig off the kernel's command line.
#
# Phases: configure (defconfig, merge fragment, olddefconfig, verify), build (make target),
# install (vmlinuz, System.map, .config; headers to dev output when present).
#
# Options:
#   kbuild.base     defconfig name or path to a .config file (default: defconfig)
#   kbuild.config   typed attrset merged into base: {NAME: "y"|"n"|"m"|freeform}
#   kbuild.configFragments  list of kconfig fragment files (CONFIG_X=y / # CONFIG_X is not set lines),
#                   merged with scripts/kconfig/merge_config.sh after base and kbuild.config, in order,
#                   so a fragment wins over both; its lines are verified after olddefconfig. Another
#                   repo's OS config appends its own through the override tree:
#                   overrides.linux-kernel.kbuild.configFragments.append = [ ./kernel.config ]
#   kbuild.target   make target (bzImage, Image, etc); null = auto from platform
#   kbuild.extraMake  extra make flags passed to every make invocation
#   kbuild.arch     override ARCH (null = from platform.names.kernel)

use ../core.nu *

export const OPTIONS = {
  base: {default: "defconfig", doc: "defconfig name or path to a .config file"}
  config: {default: {}, doc: "typed attrset: CONFIG_NAME -> y|n|m|freeform string"}
  configFragments: {default: [], doc: "kconfig fragment files merged on top of base and config, last wins"}
  target: {default: null, doc: "make target (bzImage, Image); null = auto from platform", nullable: true}
  extraMake: {default: [], doc: "extra make flags for every invocation"}
  arch: {default: null, doc: "override ARCH; null = from platform.names.kernel", nullable: true}
}

export def setup []: nothing -> nothing { }

# in-tree build
export def workdir []: nothing -> string { project-dir kbuild }

# ARCH from platform or override
def karch []: nothing -> string {
  let o = (options kbuild)
  $o.arch | default (ctx).platform.names.kernel
}

# common make flags: ARCH, jobs, LLVM, extraMake
def make-flags []: nothing -> list<string> {
  let c = (ctx)
  let o = (options kbuild)
  [$"ARCH=(karch)" $"-j($c.njobs)" "LLVM=1" "LLVM_IAS=1"] ++ $o.extraMake
}

# convert typed config attrset to fragment lines
# y -> CONFIG_NAME=y, n -> # CONFIG_NAME is not set, m -> CONFIG_NAME=m, else freeform
def config-to-fragment [config: record]: nothing -> string {
  $config | items {|name, value|
    if $value == "n" {
      $"# CONFIG_($name) is not set"
    } else if $value == "y" or $value == "m" {
      $"CONFIG_($name)=($value)"
    } else {
      # freeform: quoted string or number
      if ($value | describe) == "int" {
        $"CONFIG_($name)=($value)"
      } else {
        $"CONFIG_($name)=\"($value)\""
      }
    }
  } | str join "\n"
}

# verify that every requested option has the requested value in the final .config
def verify-config [config: record, dotconfig: string]: nothing -> nothing {
  let final = (open --raw $dotconfig | lines)
  let errors = ($config | items {|name, value|
    let want = if $value == "n" {
      $"# CONFIG_($name) is not set"
    } else if $value == "y" or $value == "m" {
      $"CONFIG_($name)=($value)"
    } else if ($value | describe) == "int" {
      $"CONFIG_($name)=($value)"
    } else {
      $"CONFIG_($name)=\"($value)\""
    }
    # also accept bare CONFIG_NAME=n (olddefconfig sometimes writes this)
    let alt = if $value == "n" { $"CONFIG_($name)=n" } else { null }
    if not (($final | any { $in == $want }) or ($alt != null and ($final | any { $in == $alt }))) {
      $"CONFIG_($name): wanted ($value), not found in .config"
    }
  } | compact)
  if ($errors | is-not-empty) {
    error make {msg: $"kbuild config verification failed:\n($errors | str join '\n')"}
  }
  note kbuild-verify $"($config | columns | length) options verified"
}

# the CONFIG_ names a fragment file sets, and its lines as `.config` spells them
def fragment-lines [files: list<string>]: nothing -> list<string> {
  $files | each {|f| open --raw $f | lines | str trim | where {|l| ($l =~ '^CONFIG_[A-Za-z0-9_]+=') or ($l =~ '^# CONFIG_[A-Za-z0-9_]+ is not set$') } } | flatten
}

def fragment-name [line: string]: nothing -> string {
  $line | parse -r '^(?:# )?CONFIG_([A-Za-z0-9_]+)' | get 0.capture0
}

# every fragment line must survive olddefconfig, the last line for a name is the one that counts
def verify-fragments [lines: list<string>, dotconfig: string]: nothing -> nothing {
  let final = (open --raw $dotconfig | lines)
  let last = ($lines | reduce -f {} {|l, acc| $acc | upsert (fragment-name $l) $l } | values)
  let errors = ($last | each {|l|
    let alt = if ($l | str starts-with "# ") { $"CONFIG_(fragment-name $l)=n" } else { null }
    if not (($final | any { $in == $l }) or ($alt != null and ($final | any { $in == $alt }))) {
      $"($l): not found in .config"
    }
  } | compact)
  if ($errors | is-not-empty) {
    error make {msg: $"kbuild fragment verification failed:\n($errors | str join '\n')"}
  }
  note kbuild-verify $"($last | length) fragment options verified"
}

# configure: defconfig or copy base, merge fragment, olddefconfig, verify
export def configure []: nothing -> nothing {
  let c = (ctx)
  let o = (options kbuild)
  let src = (project-dir kbuild)

  # start from defconfig or a given .config
  if ($o.base | str ends-with ".config") or ($o.base | path exists) {
    # explicit .config file
    cp $o.base $"($src)/.config"
    x make ...(make-flags) olddefconfig
  } else {
    # defconfig name (e.g., "defconfig", "x86_64_defconfig")
    x make ...(make-flags) $o.base
  }

  # merge the typed config, then the fragment files; later wins
  let fragments = $o.configFragments
  let overridden = (fragment-lines $fragments | each {|l| fragment-name $l } | uniq)
  if ($o.config | is-not-empty) {
    let fragment = $"($c.build)/golconda.config"
    config-to-fragment $o.config | save -f $fragment
    note kbuild-fragment $"($o.config | columns | length) options in fragment"
  }
  let files = ((if ($o.config | is-not-empty) { [$"($c.build)/golconda.config"] } else { [] }) ++ $fragments)
  if ($files | is-not-empty) {
    # merge using scripts/kconfig/merge_config.sh
    x sh $"($src)/scripts/kconfig/merge_config.sh" -m $"($src)/.config" ...$files

    # run olddefconfig to resolve dependencies
    x make ...(make-flags) olddefconfig

    # verify all requested options survived: the typed ones a fragment did not change, and the fragments
    let typed = ($o.config | columns | where { $in not-in $overridden } | reduce -f {} {|n, acc| $acc | insert $n ($o.config | get $n) })
    if ($typed | is-not-empty) { verify-config $typed $"($src)/.config" }
    if ($fragments | is-not-empty) { verify-fragments (fragment-lines $fragments) $"($src)/.config" }
  }
}

# build: make the kernel target
export def build []: nothing -> nothing {
  let c = (ctx)
  let o = (options kbuild)

  # determine target: explicit, or auto from platform
  let target = if $o.target != null { $o.target } else {
    match (karch) {
      "x86" => "bzImage"
      "arm64" => "Image"
      "riscv" => "Image"
      "loongarch" => "vmlinuz.efi"
      "powerpc" => "vmlinux"
      _ => "vmlinux"
    }
  }

  note kbuild-target $target
  x make ...(make-flags) $target
}

# install: copy vmlinuz, System.map, .config to out; headers to dev if present
export def install []: nothing -> nothing {
  let c = (ctx)
  let o = (options kbuild)
  let src = (project-dir kbuild)

  # get kernel version from Makefile
  let version = (x make ...(make-flags) -s kernelversion | complete | get stdout | str trim)
  note kbuild-version $version

  # determine installed kernel name
  let target = if $o.target != null { $o.target } else {
    match (karch) {
      "x86" => "bzImage"
      "arm64" => "Image"
      "riscv" => "Image"
      "loongarch" => "vmlinuz.efi"
      "powerpc" => "vmlinux"
      _ => "vmlinux"
    }
  }

  # find the built kernel image
  let arch_boot = match (karch) {
    "x86" => "x86/boot"
    "arm64" => "arm64/boot"
    "riscv" => "riscv/boot"
    "loongarch" => "loongarch/boot"
    "powerpc" => "powerpc/boot"
    $other => $"($other)/boot"
  }
  let kernel_path = if $target == "vmlinux" {
    $"($src)/vmlinux"
  } else {
    $"($src)/arch/($arch_boot)/($target)"
  }

  # create output directories following systemd conventions
  let moddir = $"($c.out)/lib/modules/($version)"
  mkdir $moddir

  # copy kernel artifacts
  cp $kernel_path $"($moddir)/vmlinuz"
  cp $"($src)/System.map" $"($moddir)/System.map"
  cp $"($src)/.config" $"($moddir)/config"

  # symlink at top level for convenience
  mkdir $"($c.out)/boot"
  ^ln -s $"../lib/modules/($version)/vmlinuz" $"($c.out)/boot/vmlinuz-($version)"

  note kbuild-install $"lib/modules/($version)/vmlinuz System.map config"

  # install headers to dev output if it exists
  if ($env.outputs?.dev? | default "" | is-not-empty) {
    let dev = $env.outputs.dev
    mkdir $"($dev)/lib/modules/($version)"

    # headers_install to dev
    x make ...(make-flags) INSTALL_HDR_PATH=$"($dev)" headers_install

    # copy scripts and include for out-of-tree module builds
    mkdir $"($dev)/lib/modules/($version)/build"
    for d in [scripts include] {
      if ($"($src)/($d)" | path exists) {
        cp -r $"($src)/($d)" $"($dev)/lib/modules/($version)/build/"
      }
    }

    # copy key files for module builds
    for f in [Makefile Module.symvers] {
      if ($"($src)/($f)" | path exists) {
        cp $"($src)/($f)" $"($dev)/lib/modules/($version)/build/"
      }
    }

    note kbuild-dev $"headers and build scripts to dev output"
  }

  # debug output: unstripped vmlinux with DWARF
  if ($env.outputs?.debug? | default "" | is-not-empty) {
    let debug = $env.outputs.debug
    mkdir $"($debug)/lib/debug"
    if ($"($src)/vmlinux" | path exists) {
      cp $"($src)/vmlinux" $"($debug)/lib/debug/vmlinux"
      note kbuild-debug "vmlinux with DWARF to debug output"
    }
  }
}
