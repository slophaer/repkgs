{ package }:
package {
  name = "test-tz";
  version = "1";
  bin = [ "tz" ];
  tests.version = false; # the fixture prints a zone, not a version
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        x cc tz.c -o $"($c.out)/bin/tz"
      '';
    }
  ];
}
