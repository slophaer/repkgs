# bc: arbitrary precision calculator language (modern implementation by Gavin Howard)
# This is a simple, dependency-free implementation that works without readline/ed.
{ package }:
package {
  name = "bc";
  # on windows it builds with Visual Studio (vs/), not configure.sh: its _WIN32 code takes MSVC's
  # <Windows.h> spelling and share modes (_SH_DENYNO), which mingw lacks. msvc stays listed for
  # whenever that is wired up
  platforms.libc = [
    "glibc"
    "musl"
    "apple"
    "msvc"
  ];

  # bc's own configure.sh, not autotools
  uses = [ "make" ];
  make.configureScript = "./configure.sh";
  make.configureFlags = [
    "--disable-nls"
    "--disable-history"
    "--disable-man-pages"
    "--disable-strip" # keep symbols: finish splits debug info itself
    "--disable-generated-tests" # they compute expected results with a system bc
    "--disable-problematic-tests" # bc error test 33.txt grew to 58 GB here (Linux overcommit)
  ];
  # configure.sh compiles gen/strgen with $HOSTCC, else $CC, and runs it here: cross, $CC is the
  # target's compiler
  phases.before."make.configure" = [
    {
      name = "hostcc";
      run = "$env.HOSTCC = $env.CC_FOR_BUILD";
    }
  ];
  make.testTarget = [ "test" ]; # bc's Makefile has no check

  bin = [
    "bc"
    "dc"
  ];
  tests.version = "bc --version";
}
