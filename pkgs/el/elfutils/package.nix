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

  # elfutils builds with -Werror; clang flags const-discarding casts, and tests/varlocs.c sets a
  # global it never reads (-Wunused-but-set-global)
  cc.cflags = [
    "-Wno-error=incompatible-pointer-types-discards-qualifiers"
    "-Wno-error=unused-but-set-global"
  ];

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
  # Expected failures with an LLVM toolchain; an XPASS fails the build, so a fix shows up:
  #  - elflint --gnu-ld checks GNU ld output and rejects lld's (".relro_padding has wrong type:
  #    expected RELR, is NOBITS"); the strip and reverse-sections tests run elflint on the result
  #  - arsymtest runs `$NM -s` (GNU nm's armap flag); llvm-nm's -s takes two arguments
  #  - getphdrnum: readelf prints e_phnum 0xffff as 65535, the expected output says -1
  #  - backtrace-data: the unwind stops at start_thread ("data: no main")
  autotools.testTarget = [
    "check"
    "XFAIL_TESTS=run-elflint-self.sh run-strip-strmerge.sh run-reverse-sections-self.sh run-arsymtest.sh run-getphdrnum.sh run-backtrace-data.sh"
  ];
  tests.version = "eu-readelf --version";

  # Remove eu-make-debug-archive which has hardcoded paths to other elfutils binaries
  patches = [ ./relocatable.patch ];
}
