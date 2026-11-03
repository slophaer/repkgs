# a program whose interpreter and libz are found relative to it ($ORIGIN), for the execfn test
{ package, pkgs }:
package {
  name = "test-execfn";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        x cc main.c -lz -o $"($c.out)/bin/zv"
      '';
    }
  ];
  dependencies = [ pkgs.zlib ];
  bin = [ "zv" ];
  tests.version = "zv";
}
