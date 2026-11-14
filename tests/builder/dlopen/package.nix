# Binaries that name libraries only in .note.dlopen, with no -rpath for them (the builder adds it):
# dlz names libz.so.1 of a dependency and is linked from a thin archive, as meson links its
# internal static libraries; dlself names the package's own libself.so.1. And libsib.so.1, which
# dlopen()s its sibling libself.so.1 with no note at all. finish's dlopen-check holds the notes
# to the RUNPATH the builder wrote
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
        x cc -c main.c -o main.o
        x llvm-ar rcsT libdlz.a main.o
        x cc -Wl,--whole-archive libdlz.a -Wl,--no-whole-archive -o $"($c.out)/bin/dlz"
        x cc -shared -fPIC self.c -Wl,-soname,libself.so.1 -o $"($c.out)/lib/libself.so.1"
        x cc dlself.c -o $"($c.out)/bin/dlself"
        x cc -shared -fPIC sib.c -Wl,-soname,libsib.so.1 -o $"($c.out)/lib/libsib.so.1"
        x cc dlsib.c $"-L($c.out)/lib" -l:libsib.so.1 -o $"($c.out)/bin/dlsib"
      '';
    }
  ];
  dependencies = [ pkgs.zlib ];
  bin = [
    "dlz"
    "dlself"
    "dlsib"
  ];
  # prints "zlib 1.x"
  tests.version = "dlz";
}
