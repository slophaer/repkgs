{ package }:
package {
  name = "ripgrep";
  license = "Unlicense OR MIT"; # COPYING: dual-licensed under the Unlicense and MIT
  uses = [ "cargo" ];
  cargo.features = [ "pcre2" ];
  bin = [ "rg" ];
}
