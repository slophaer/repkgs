# Cross-library placement is checked at eval; the native build proves the complete bin list.
{
  system ? builtins.currentSystem,
}:
let
  set = import ../nix/set.nix { inherit system; };
  crossName = if set.platform.cpu == "aarch64" then "x86_64-linux" else "aarch64-linux";
  cross =
    (import ../nix/set.nix {
      inherit system;
      platform = crossName;
    }).pkgs.elfutils;
  pkg = set.pkgs.elfutils;
  seed = set.bootstrap.seed;
in
assert
  builtins.all (d: d.platform == crossName) cross.args.dependencies
  || throw "elfutils: linked libraries must use the target platform";
assert builtins.stringLength cross.drvPath > 0;
assert
  builtins.all (b: builtins.elem b pkg.args.bin) [
    "eu-addr2line"
    "eu-elfclassify"
    "eu-unstrip"
  ]
  || throw "elfutils: the binary declaration omits installed tools";
derivation {
  name = "check-elfutils";
  inherit system pkg;
  declared = builtins.toJSON pkg.args.bin;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  PATH = "${seed}/bin";
  builder = "${seed}/bin/nu";
  args = [
    "--no-config-file"
    "--include-path=${./builder/lib}"
    "${./elfutils/test.nu}"
  ];
}
