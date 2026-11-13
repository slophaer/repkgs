# an out-of-tree package for tests/set.nix: evaluated, never built
{ package }:
package {
  name = "set-plain";
  version = "1";
  source = ./.;
  install."share/set-plain/package.nix" = ./package.nix;
}
