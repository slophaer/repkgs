{
  system ? builtins.currentSystem,
}:
let
  set = import ../nix/set.nix { inherit system; };
  seed = set.bootstrap.seed;
  sep = builtins.fromJSON ''"\u001e"'';
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
    "--include-path=${../pkgs/up/uptrack/src}${sep}${./builder/lib}"
    "${./uptrack/test.nu}"
  ];
}
