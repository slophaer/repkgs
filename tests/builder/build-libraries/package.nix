# Test: buildLibraries are found by the build machine's compiler and pkg-config, with no flags in
# the package, and the program it links runs during the build
{
  package,
  buildPkgs,
}:
package {
  name = "test-build-libraries";
  version = "1";
  source = ./src;
  buildDependencies = [ buildPkgs.pkgconf ];
  buildLibraries = [ buildPkgs.zlib ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/share"
        # a generator: built for and run on the build machine, its output goes in the package
        x $env.CC_FOR_BUILD gen.c -lz -o gen
        ^./gen | save $"($c.out)/share/zlib-version"
        ^$env.PKG_CONFIG_FOR_BUILD --modversion zlib | save $"($c.out)/share/pc-version"
      '';
    }
  ];
  tests.version = false;
}
