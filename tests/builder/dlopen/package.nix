# a binary that names libz.so.1 only in .note.dlopen. It passes zlib's lib dir as an rpath (what a
# dlopen user must do: jig keeps a dir that served no NEEDED); finish's dlopen-check holds it to that
{ package, pkgs }:
package {
  name = "test-dlopen";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        x cc main.c -o $"($c.out)/bin/dlz"
      '';
    }
  ];
  dependencies = [ pkgs.zlib ];
  cc.ldflags = [ "-Wl,-rpath,${pkgs.zlib}/lib" ];
  bin = [ "dlz" ];
  # prints "zlib 1.x"
  tests.version = "dlz";
}
