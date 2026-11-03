# A libc can leave the sysroot only when it carries the patched unwinder.
{
  system ? builtins.currentSystem,
}:
let
  boot = import ../bootstrap { inherit system; };
  platforms = import ../nix/platforms.nix;
  native = boot.toolchain.${system} { };
  cross = builtins.filter (p: p.os == "linux" && p.name != system) (
    builtins.attrValues platforms.byName
  );
in
assert boot.stage1.cc.libcOut == boot.stage1.sysroot;
assert native.cc.libcOut == native.libc;
assert builtins.all (
  p:
  let
    target = boot.toolchain.${p.name} { };
  in
  target.cc.libcOut == target.sysroot
) cross;
derivation {
  name = "check-bootstrap-libc";
  inherit system;
  builder = "${boot.seed}/bin/nu";
  args = [
    "--no-config-file"
    "-c"
    "mkdir $env.out"
  ];
}
