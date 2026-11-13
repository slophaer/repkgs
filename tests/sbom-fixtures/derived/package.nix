# tests/sbom.nix: built from another package's source (jq's), with no sources.toml. Evaluated only
{ package, pkgs }:
package {
  name = "sbom-derived";
  version = "1";
  source = ./.;
  sourceOf = {
    package = pkgs.jq;
    subpath = "src";
  };
  install."share/sbom-derived/package.nix" = ./package.nix;
}
