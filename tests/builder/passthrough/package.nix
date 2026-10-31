{ package }:
package {
  name = "test-passthrough";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/lib"
        x cc -c p.c -o $"($c.out)/lib/normal.o"
        with-env {JIG_PASSTHROUGH: "1"} { x cc -c p.c -o $"($c.out)/lib/raw.o" }
      '';
    }
  ];
  tests.run = false;
}
