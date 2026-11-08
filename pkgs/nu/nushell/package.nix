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
  # the commands a feature brings: a feature dropped from the list above drops them silently
  # (uptrack needs `http get`)
  phases.after."cargo.install" = [
    {
      name = "commands";
      run = ''
        if not $c.platform.cross {
          let have = (^$"($c.out)/bin/nu" --no-config-file -c 'scope commands | get name | to json' | from json)
          let missing = (["http get" "ps" "sys host"] | where $it not-in $have)
          if ($missing | is-not-empty) { error make {msg: $"nushell lacks ($missing | str join ', ')"} }
        }
      '';
    }
  ];
  bin = [ "nu" ];
}
