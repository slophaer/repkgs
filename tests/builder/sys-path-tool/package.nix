# An ordinary dependency with a program: its bin/ goes on PATH as before
{ package }:
package {
  name = "test-sys-path-tool";
  version = "1";
  source = ./.;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        "#!/bin/sh\necho tool\n" | save $"($c.out)/bin/tool"
        ^chmod +x $"($c.out)/bin/tool"
      '';
    }
  ];
  bin = [ "tool" ];
  tests.version = false;
}
