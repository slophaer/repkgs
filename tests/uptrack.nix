{
  system ? builtins.currentSystem,
}:
let
  set = import ../nix/set.nix { inherit system; };
  seed = set.bootstrap.seed;
  sep = builtins.fromJSON ''"\u001e"'';
  # pipeline.nu imports builder/sys-libs.nu relative to the repository root.
  src = builtins.path {
    path = ../.;
    name = "uptrack-test-source";
    filter = p: _: baseNameOf p != ".git";
  };
in
derivation {
  name = "check-uptrack";
  inherit system;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  PATH = "${set.pkgs.git}/bin:${seed}/bin";
  builder = "${seed}/bin/nu";
  args = [
    "--no-config-file"
    "--include-path=${src}/pkgs/up/uptrack/src${sep}${./builder/lib}"
    "${./uptrack/test.nu}"
  ];
}
