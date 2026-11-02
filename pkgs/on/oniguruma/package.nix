{ package }:
package {
  name = "oniguruma";
  uses = [ "autotools" ];
  bin = [ "onig-config" ];
  autotools.configureScript = "configure";
}
