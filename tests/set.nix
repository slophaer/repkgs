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

  drv = p: p.drvPath;
  flags = x: { autotools.flags.append = [ x ]; };
  # set.variant: one package again, with a tree on top of the set's overrides
  local = {
    set-plain = ./set-fixtures/plain;
    set-featured = ./set-fixtures/featured;
  };
  withLocal = setWith { packages = local; };
  overridden = setWith { overrides.jq = flags "--a"; };
  # set.extend: the set again with more arguments
  extended = set.extend { overrides.oniguruma = flags "--x"; };
  reimported = setWith { overrides.oniguruma = flags "--x"; };
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

# variant: no tree is the package itself, a tree is what `overrides.<name>` makes
assert drv (set.variant "jq" { }) == drv pkgs.jq;
assert drv (set.variant "jq" (flags "--a")) == drv overridden.pkgs.jq;
assert drv (set.variant "jq" (flags "--a")) != drv pkgs.jq;
# on top of the set's own overrides, in that order
assert
  drv (overridden.variant "jq" (flags "--b")) == drv
    (setWith {
      overrides = [
        { jq = flags "--a"; }
        { jq = flags "--b"; }
      ];
    }).pkgs.jq;
# features as in overrides.<name>.features
assert
  drv (withLocal.variant "set-featured" { features.flavour = "salted"; }) == drv
    (setWith {
      packages = local;
      overrides.set-featured.features.flavour = "salted";
    }).pkgs.set-featured;
assert
  (withLocal.variant "set-featured" { features.flavour = "salted"; }).features.flavour == "salted";
# re-made from its own package.nix: an in-tree variant (cmake is `variant pkgs.cmake-bootstrap`),
# an out-of-tree package, an alias
assert drv (set.variant "cmake" { }) == drv pkgs.cmake;
assert drv (withLocal.variant "set-plain" { }) == drv withLocal.pkgs.set-plain;
assert drv (set.variant "cpython" { }) == drv pkgs.cpython314;
assert fails (set.variant "no-such-package" { });
assert fails (set.variant "jq" { no-such-field.set = 1; });

# extend: the same set as one imported with the arguments combined. A dependent of the changed
# package changes, the rest keeps its derivation
assert drv extended.pkgs.oniguruma == drv reimported.pkgs.oniguruma;
assert drv extended.pkgs.jq == drv reimported.pkgs.jq;
assert drv extended.pkgs.jq != drv pkgs.jq;
assert drv extended.pkgs.zlib == drv pkgs.zlib;
# overrides go after the set's, packages and features are merged
assert
  drv (overridden.extend { overrides.jq = flags "--b"; }).pkgs.jq == drv
    (setWith {
      overrides = [
        { jq = flags "--a"; }
        { jq = flags "--b"; }
      ];
    }).pkgs.jq;
assert
  drv
    (withLocal.extend {
      features.flavour = "salted";
    }).pkgs.set-featured == drv
    (setWith {
      packages = local;
      features.flavour = "salted";
    }).pkgs.set-featured;
assert (set.extend { packages = local; }).pkgs.set-plain.pname == "set-plain";
# the result is a set like any other
assert drv ((set.extend { }).variant "jq" (flags "--a")) == drv overridden.pkgs.jq;
assert fails (set.extend { platform = "aarch64-linux"; });
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
