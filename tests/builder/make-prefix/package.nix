# Test: the make builder with a declared prefix, and staged roots outside it kept or dropped
{ package }:
package {
  name = "test-make-prefix";
  version = "1";
  source = ./src;
  uses = [ "make" ];
  prefix = "/usr";
  stagedRoots = {
    "/etc" = "share/factory/etc";
    "/var" = null;
  };
  bin = [ "hello" ];
  tests.run = false;
  tests.version = false;
}
