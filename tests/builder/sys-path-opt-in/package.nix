# Runs a system library's program (as dbmate runs sqlite3): sysTools puts that bin/ back on PATH
{ package, pkgs }:
package {
  name = "test-sys-path-opt-in";
  version = "1";
  source = ./.;
  sys = [ "test-sys-path-lib" ];
  sysTools = [ "test-sys-path-lib" ];
  dependencies = [ pkgs.test-sys-path-tool ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        "#!/bin/sh\necho main\n" | save $"($c.out)/bin/main"
        ^chmod +x $"($c.out)/bin/main"
      '';
    }
  ];
  bin = [ "main" ];
  tests.version = false;
}
