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
  # `license`: an SPDX expression, read at evaluation, never a build input
  withLicense = l: (setWith { overrides.jq.license.set = l; }).pkgs.jq;
  licensed = setWith { packages.set-licensed = ./set-fixtures/licensed; };
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
# `license` is the SPDX expression the recipe writes, null when it writes none
assert pkgs.bash.license == "GPL-3.0-or-later";
assert pkgs.ripgrep.license == "Unlicense OR MIT";
assert pkgs.jq.license == null;
assert licensed.pkgs.set-licensed.license == "Apache-2.0 OR MIT";
assert (withLicense "MIT").license == "MIT";
# the key changes no derivation: each recipe that has one, without it (a recipe elsewhere says it
# in its own package.nix, the same key), and a recipe that has none, with one
assert builtins.all
  (
    n:
    let
      without = (setWith { overrides.${n}.license.remove = true; }).pkgs.${n};
    in
    without.license == null && drv without == drv pkgs.${n}
  )
  [
    "bash"
    "ncurses"
    "unzip"
    "zlib"
    "ripgrep"
  ];
assert drv (withLicense "MIT") == drv pkgs.jq;
assert drv (withLicense "Apache-2.0 OR MIT") == drv (withLicense "GPL-3.0-or-later");
assert !(pkgs.bash.spec ? license);
# what an expression may be: ids with `+`, AND, OR, WITH, brackets, LicenseRef-
assert builtins.all (l: (withLicense l).license == l) [
  "MIT"
  "Apache-2.0 OR MIT"
  "GPL-3.0-or-later"
  "Apache-2.0+"
  "GPL-2.0-only WITH Classpath-exception-2.0"
  "(MIT OR Apache-2.0) AND Zlib"
  "((MIT))"
  "LicenseRef-vendor-1.0"
  "DocumentRef-spdx-tool-1.2:LicenseRef-MyLicense"
];
# and what it may not: another type, an empty string, a dangling or doubled operator, a lower-case
# operator, a space inside an id, unbalanced brackets, a character no id has
assert builtins.all (l: fails (withLicense l).license) [
  1
  true
  null
  [ "MIT" ]
  { id = "MIT"; }
  ""
  " "
  "MIT AND"
  "OR MIT"
  "MIT OR OR Apache-2.0"
  "MIT Apache-2.0"
  "MIT or Apache-2.0"
  "GNU GPL"
  "(MIT OR Apache-2.0"
  "MIT)"
  "MIT/Apache-2.0"
  "MIT, Apache-2.0"
  "MIT WITH"
  "()"
];
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
