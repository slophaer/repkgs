# Test: autotools autoreconf with pkg.m4 and libtool.m4 from build tools
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "test-autotools";
  version = "1.0";
  source = ./src;
  uses = [ "autotools" ];
  phases.before."autotools.configure" = [
    {
      name = "autoreconf";
      run = ''
        cd $c.src
        x autoreconf -fi
      '';
    }
  ];
  buildDependencies = [
    buildPkgs.autoconf
    buildPkgs.automake
    buildPkgs.libtool # provides libtool.m4, ltoptions.m4
    buildPkgs.pkgconf # provides pkg.m4
  ];
  dependencies = [
    pkgs.zlib # for PKG_CHECK_MODULES test
  ];
  bin = [ "hello" ];
  tests.run = false;
  tests.version = false;
}
