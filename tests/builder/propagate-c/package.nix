# Package C: a library that exports env vars. B propagates it, A should see the env.
{ package }:
package {
  name = "test-propagate-c";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/lib" $"($c.out)/share" $"($c.out)/include"
        x cc -shared -fPIC lib.c -o $"($c.out)/lib/libc_propagate.so"
        cp c.h $"($c.out)/include/"
        "data from C" | save $"($c.out)/share/c-data.txt"
      '';
    }
  ];
  exports = {
    env.FOO = "{root}/share";
    env.C_MARKER = "from-c";
  };
  tests.version = false;
}
