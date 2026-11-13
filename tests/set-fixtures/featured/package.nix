# an out-of-tree package with a feature, for tests/set.nix: evaluated, never built
{ package, features }:
package {
  name = "set-featured";
  version = "1";
  source = ./.;
  features.flavour = {
    default = "plain";
    values = [
      "plain"
      "salted"
    ];
  };
  env.FLAVOUR = features.flavour;
  install."share/set-featured/package.nix" = ./package.nix;
}
