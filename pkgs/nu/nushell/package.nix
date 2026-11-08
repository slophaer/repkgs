{ package }:
package {
  name = "nushell";
  uses = [ "cargo" ];
  # default features minus plugin + system-clipboard (x11/wayland); `network` (http, the
  # commands uptrack polls with) is one of them
  cargo.noDefaultFeatures = true;
  cargo.features = [
    "network"
    "sqlite"
    "trash-support"
    "rustls-tls"
  ];
  tests.run = false; # the suite spawns `nu` against a home directory and a tty
  bin = [ "nu" ];
}
