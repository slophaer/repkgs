# Links a system library ([pin] sys) and has an ordinary dependency: only the dependency's bin/ is
# on the launcher's PATH, the library's is not (its programs are not this package's tools)
{ package, pkgs }:
package {
  name = "test-sys-path";
  version = "1";
  source = ./.;
  sys = [ "test-sys-path-lib" ];
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
