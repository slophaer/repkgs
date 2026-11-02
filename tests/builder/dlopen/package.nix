# a binary that names libz.so.1 only in .note.dlopen, and one that names the package's own
# libself.so.1. Each passes its library's lib dir as an rpath (what a dlopen user must do: jig keeps
# a dir that served no NEEDED); finish's dlopen-check holds it to that, dependencies and its own lib/
{ package, pkgs }:
package {
  name = "test-dlopen";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin" $"($c.out)/lib"
        x cc main.c -o $"($c.out)/bin/dlz"
        x cc -shared -fPIC self.c -Wl,-soname,libself.so.1 -o $"($c.out)/lib/libself.so.1"
        x cc dlself.c '-Wl,-rpath,$ORIGIN/../lib' -o $"($c.out)/bin/dlself"
      '';
    }
  ];
  dependencies = [ pkgs.zlib ];
  cc.ldflags = [ "-Wl,-rpath,${pkgs.zlib}/lib" ];
  bin = [ "dlz" "dlself" ];
  # prints "zlib 1.x"
  tests.version = "dlz";
}
