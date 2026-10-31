# bc: arbitrary precision calculator language (modern implementation by Gavin Howard)
# This is a simple, dependency-free implementation that works without readline/ed.
{ package, buildPkgs }:
package {
  name = "bc";

  # Uses custom configure.sh script, not autotools
  uses = [ "make" ];

  # Configure with POSIX-compliant bc (no GNU extensions needed for kernel)
  make.configureScript = "./configure.sh";
  make.configureFlags = [ "--disable-nls" "--disable-history" "--disable-man-pages" ];

  bin = [ "bc" "dc" ];
  tests.run = false;
  tests.version = "bc --version";

  # bc strips binaries itself, so disable debug info check
  debug = false;
}
