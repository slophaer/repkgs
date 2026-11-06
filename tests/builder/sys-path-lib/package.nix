# A system library that also ships a program (as sqlite ships sqlite3): what [pin] sys names
{ package }:
package {
  name = "test-sys-path-lib";
  version = "1";
  source = ./.;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        "#!/bin/sh\necho lib-tool\n" | save $"($c.out)/bin/lib-tool"
        ^chmod +x $"($c.out)/bin/lib-tool"
      '';
    }
  ];
  bin = [ "lib-tool" ];
  tests.version = false;
}
