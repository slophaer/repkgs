# Test: bindgen parses libc and dependency headers with no sysroot or include flags in the package
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "test-bindgen";
  version = "1";
  source = ./src;
  buildDependencies = [
    buildPkgs.bindgen
    buildPkgs.clang
  ];
  dependencies = [ pkgs.zlib ];
  # bindgen dlopens libclang from here (pkgs/bi/bindgen)
  env.LIBCLANG_PATH = "${buildPkgs.clang}/lib";
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/share"
        x bindgen wrapper.h -o $"($c.out)/share/bindings.rs" --allowlist-function "zlibVersion|snprintf"
      '';
    }
  ];
  tests.version = false;
}
