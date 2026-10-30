# automake: generates Makefile.in from Makefile.am
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "automake";
  uses = [ "autotools" ];
  patches = [ ./relocatable.patch ];
  # perl scripts that invoke autoconf and m4
  dependencies = [
    pkgs.perl
    pkgs.autoconf
  ];
  buildDependencies = [
    buildPkgs.perl
    buildPkgs.autoconf
  ];
  # the test suite takes hours and needs many tools we don't have
  tests.run = false;
  bin = [
    "automake"
    "aclocal"
  ];
}
