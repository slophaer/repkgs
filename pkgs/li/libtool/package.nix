# libtool: generic library support script
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "libtool";
  uses = [ "autotools" ];
  patches = [ ./relocatable.patch ];
  autotools.flags = [
    "--disable-ltdl-install" # don't install libltdl; libtool's macros and script work without it
  ];
  # Touch the man pages so they don't get regenerated (we don't have help2man)
  phases.before."autotools.build" = [
    {
      name = "man-uptodate";
      run = ''^touch ...(files $"($c.src)/doc/*.1")'';
    }
  ];
  # libtool and libtoolize are shell scripts that need various tools on PATH
  dependencies = [
    pkgs.m4
    pkgs.bash
    pkgs.coreutils
    pkgs.sed
    pkgs.grep
  ];
  buildDependencies = [
    buildPkgs.m4
    buildPkgs.bash
  ];
  # tests take a long time
  tests.run = false;
  bin = [
    "libtool"
    "libtoolize"
  ];
}
