# bc: arbitrary precision calculator language (modern implementation by Gavin Howard)
# This is a simple, dependency-free implementation that works without readline/ed.
{ package }:
package {
  name = "bc";

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
  make.testTarget = [ "test" ]; # bc's Makefile has no check

  bin = [
    "bc"
    "dc"
  ];
  tests.version = "bc --version";
}
