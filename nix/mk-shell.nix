# A development shell made of this set's packages, for a flake that wants the tools without
# nixpkgs' mkShell. Neither nix-shell (direnv's `use nix`) nor `nix develop` builds it: both
# source `$stdenv/setup` and evaluate `shellHook`, `nix develop` after swapping the builder's
# arguments for its own get-env.sh. Two consequences shape the derivation below.
#
#   - The builder must be called `bash`. develop.cc refuses anything else: "'nix develop' only
#     works on derivations that use 'bash' as their builder". A nu builder, which every package
#     of this set uses, cannot be entered.
#   - The search paths come from `$stdenv/setup`, a few exports, not from attributes: an
#     attribute PATH would replace the caller's under nix-shell, and under --pure leave none.
#     setup puts the shell's packages, then `baseTools`, before the caller's entries, as
#     nixpkgs' stdenv does with its own: `nix-shell --pure` and `nix develop -i`, which keep none
#     of the caller's, still have ls, rm and sh (and their own rc scripts work).
#
# `nix develop` prepends PATH to the caller's rather than replacing it.
{
  platform,
  toolchain,
  bash,
  seed,
  # the set's base userland and bash: coreutils, findutils, grep, sed, ... but no compiler
  defaultBaseTools,
  lib,
}:
{
  name ? "repkgs-shell",
  # their bin/ goes on PATH, their lib/pkgconfig on PKG_CONFIG_PATH
  packages ? [ ],
  # the set's own cc wrapper, so `cc`, `c++` and the linker in the shell are the ones every
  # package here was built with. false for a shell that compiles nothing
  cc ? true,
  # more variables, and a script to evaluate on entry
  env ? { },
  shellHook ? "",
  # on PATH after the packages, before the caller's. [ ] for the packages alone: `nix-shell
  # --pure` and `nix develop -i` then miss rm, and their own rc scripts fail
  baseTools ? defaultBaseTools,
}:
let
  all = packages ++ lib.on cc [ toolchain ];
  under' = sub: ps: lib.join ":" (map (p: "${p}/${sub}") ps);
  under = sub: under' sub all;
  # VAR VALUE: VALUE, then what VAR held if anything. Nothing for no VALUE: an empty entry in
  # PATH is the working directory
  prepend = var: value: if value == "" then "" else "export ${var}=\"${value}\${${var}:+:\$${var}}\"";
  setup = lib.join "\n" (
    builtins.filter (l: l != "") [
      # nix develop sources it in the build sandbox, where PATH is a placeholder
      ''if [ "''${PATH:-}" = /path-not-set ]; then unset PATH; fi''
      (prepend "PATH" (under' "bin" (all ++ baseTools)))
      (prepend "PKG_CONFIG_PATH" (under "lib/pkgconfig"))
      (prepend "CMAKE_PREFIX_PATH" (lib.join ":" (map toString all)))
      # nix-shell runs shellHook through `runHook shellHook`, only when setup defines it
      ''runHook() { eval "eval \"\''${$1:-}\""; }''
    ]
  );
  stdenv = derivation {
    name = "${name}-stdenv";
    inherit (platform) system;
    inherit setup;
    builder = "${bash}/bin/bash";
    args = [
      "-c"
      ''${seed}/bin/mkdir $out && printf '%s\n' "$setup" > $out/setup''
    ];
  };
  shell = derivation (
    {
      inherit name shellHook stdenv;
      inherit (platform) system;
      # get-env.sh walks `$outputs` to find where to write, and nix puts that variable in the
      # environment only for a derivation that names its outputs. Without it the build writes
      # nothing and `nix develop` fails with "failed to produce output path".
      outputs = [ "out" ];
      builder = "${bash}/bin/bash";
      # only reached by building the shell, which no one wants
      args = [
        "-c"
        "echo 'this is a dev shell, enter it with `nix-shell` or `nix develop`' >&2; exit 1"
      ];
    }
    // env
  );
in
shell
// {
  # Everything the shell needs, as one derivation that can be built. nixpkgs' mkShell carries
  # the same attribute, and a NixOS test that must run offline realises it to get the closure
  # into the guest's store.
  inputDerivation = derivation {
    name = "${name}-inputs";
    inherit (platform) system;
    builder = "${bash}/bin/bash";
    args = [
      "-c"
      ''printf '%s\n' $paths > $out''
    ];
    paths = all ++ [ stdenv ];
  };
}
