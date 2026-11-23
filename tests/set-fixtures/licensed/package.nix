# an out-of-tree package with a licence for tests/set.nix: evaluated, never built
{ package }:
package {
  name = "set-licensed";
  version = "1";
  source = ./.;
  license = "Apache-2.0 OR MIT";
  install."share/set-licensed/package.nix" = ./package.nix;
}
