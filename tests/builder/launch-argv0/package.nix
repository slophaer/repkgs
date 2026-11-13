# bin/hello behind a launcher (a dependency's bin/ goes on its PATH), and libexec/exec-as, which
# execs a file with any argv[0], for the launch-argv0 test
{ package, pkgs }:
package {
  name = "test-launch-argv0";
  version = "1";
  source = ./src;
  dependencies = [ pkgs.test-sys-path-tool ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin" $"($c.out)/libexec"
        x cc hello.c -o $"($c.out)/bin/hello"
        x cc exec-as.c -o $"($c.out)/libexec/exec-as"
      '';
    }
  ];
  tests.version = false;
}
