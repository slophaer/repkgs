# libelf, libdw and the eu-* tools. perf needs libelf and libdw for symbols and DWARF.
# debuginfod is off: the server wants libmicrohttpd and the client wants curl at runtime, and
# nothing here asks for either.
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "elfutils";
  # argp and obstack are glibc's, and the sources use them unconditionally
  platforms.libc = [ "glibc" ];
  uses = [ "autotools" ];
  autotools.flags = [
    "--disable-debuginfod"
    "--disable-libdebuginfod"
    "--disable-nls"
    # every tool still compiles LOCALEDIR in, and an output that names its own install prefix
    # is not relocatable. With nls off nothing reads it, so it goes where the man pages go
    "--localedir=/usr/share/locale"
    "--enable-deterministic-archives"
  ];
  # the tree builds with -Werror; clang flags const-discarding casts, and tests/varlocs.c sets a
  # global it never reads (-Wunused-but-set-global)
  cc.cflags = [
    "-Wno-error=incompatible-pointer-types-discards-qualifiers"
    "-Wno-error=unused-but-set-global"
  ];
  dependencies = [
    pkgs.zlib
    pkgs.bzip2
    pkgs.xz
    pkgs.zstd
  ];
  buildDependencies = [
    buildPkgs.m4
    buildPkgs.bison
    buildPkgs.flex
  ];
  phases.after."autotools.install" = {
    name = "scrub";
    run = ''
      # eu-make-debug-archive is a shell script whose UNSTRIP and AR defaults are
      # $out/bin/eu-*, and no relocatable output may name its own install prefix. The script
      # is the only file left that does, so point it beside itself.
      let f = $"($c.out)/bin/eu-make-debug-archive"
      open --raw $f | str replace -a $"($c.out)/bin/" '$(dirname "$0")/' | save -f $f
    '';
  };
  bin = [
    "eu-addr2line"
    "eu-ar"
    "eu-elfclassify"
    "eu-elfcmp"
    "eu-elfcompress"
    "eu-elflint"
    "eu-findtextrel"
    "eu-make-debug-archive"
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
  #  - backtrace-data: the unwind stops at start_thread ("data: no main")
  autotools.testTarget = [
    "check"
    "XFAIL_TESTS=run-elflint-self.sh run-strip-strmerge.sh run-reverse-sections-self.sh run-arsymtest.sh run-backtrace-data.sh"
  ];
  # run-readelf-compressed.sh compresses its fixture with the bzip2 program
  tests.dependencies = [ buildPkgs.bzip2 ];
  tests.version = "eu-readelf --version";
}
