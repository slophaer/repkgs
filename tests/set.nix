# nix/set.nix: what the set exposes and refuses, asserted at evaluation (nothing is built but an
# empty marker).   nix-build tests/set.nix
{
  system ? builtins.currentSystem,
}:
let
  setWith = args: import ../nix/set.nix ({ inherit system; } // args);
  set = setWith { };
  inherit (set) pkgs;
  fails = v: !(builtins.tryEval (builtins.deepSeq v true)).success;

  # an out-of-tree package under an alias's name would be hidden by the alias
  aliased = setWith { packages.cpython = ./set-fixtures/plain; };
in
# `bin` is the declared list after overrides, null when the package declares none
assert pkgs.gnumake.bin == [ "make" ];
assert pkgs.jq.bin == null;
assert
  (setWith { overrides.gnumake.bin.append = [ "gmake" ]; }).pkgs.gnumake.bin == [
    "make"
    "gmake"
  ];
# reading it changes nothing in the derivation
assert pkgs.gnumake.drvPath == (setWith { }).pkgs.gnumake.drvPath;
# a package named like an alias is an error, not silently replaced by the alias
assert fails (builtins.attrNames aliased.pkgs);
assert (setWith { packages.set-plain = ./set-fixtures/plain; }).pkgs.set-plain.pname == "set-plain";
derivation {
  name = "set-test";
  inherit system;
  builder = "${set.bootstrap.seed}/bin/nu";
  args = [
    "--no-config-file"
    "-c"
    "mkdir $env.out"
  ];
}
