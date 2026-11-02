# elfutils: libraries and utilities for handling ELF files
# Provides libelf which is needed for kernel's objtool
{ package, pkgs }:
package {
  name = "elfutils";

  uses = [ "autotools" ];

  # Disable debuginfod (network) and avoid problematic features
  # Set localedir to . to avoid hardcoded paths
  autotools.flags = [
    "--disable-debuginfod"
    "--disable-libdebuginfod"
    "--disable-nls"
    "--localedir=/"
  ];

  # Disable clang -Werror for const-discard pointer casts
  cc.cflags = [ "-Wno-error=incompatible-pointer-types-discards-qualifiers" ];

  dependencies = [
    pkgs.zlib
    pkgs.zstd
  ];

  bin = [
    "eu-addr2line"
    "eu-ar"
    "eu-elfclassify"
    "eu-elfcmp"
    "eu-elfcompress"
    "eu-elflint"
    "eu-findtextrel"
    "eu-nm"
    "eu-objdump"
    "eu-ranlib"
    "eu-readelf"
    "eu-size"
    "eu-srcfiles"
    "eu-stack"
    "eu-strings"
    "eu-strip"
    "eu-unstrip"
  ];
  tests.run = false;
  tests.version = "eu-readelf --version";

  # Remove eu-make-debug-archive which has hardcoded paths to other elfutils binaries
  patches = [ ./relocatable.patch ];
}
