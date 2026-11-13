# tests/sbom.nix: a source of its own that no sources.toml pins (`upstream`). Evaluated only
{ package }:
package {
  name = "sbom-upstream";
  version = "3";
  source = ./.;
  upstream = {
    purl = "pkg:generic/sbom-upstream";
    cpe = "cpe:2.3:a:example:sbom-upstream:{version}:*:*:*:*:*:*:*";
  };
  install."share/sbom-upstream/package.nix" = ./package.nix;
}
