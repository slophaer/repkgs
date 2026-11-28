{ package }:
package {
  name = "dash";
  license = "BSD-3-Clause AND GPL-2.0-or-later"; # COPYING: BSD for the shell, GPL for the mksignames helper
  uses = [ "autotools" ];
  bootstrapTools = true;
  tests.run = false; # no test suite in the tarball
  tests.version = false; # dash has no --version
  links."bin/sh" = "dash";
  bin = [
    "dash"
    "sh"
  ];
}
