# openssl reads its own openssl.cnf by default, not the build machine's /etc/ssl/openssl.cnf
#   nix-build tests/openssl.nix
{
  system ? builtins.currentSystem,
}:
let
  set = import ../nix/set.nix { inherit system; };
  seed = set.bootstrap.seed;
in
derivation {
  name = "check-openssl";
  inherit system;
  pkg = set.pkgs.openssl;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  PATH = "${seed}/bin";
  builder = "${seed}/bin/nu";
  args = [
    "--no-config-file"
    "--include-path=${./builder/lib}"
    "${./openssl/test.nu}"
  ];
}
