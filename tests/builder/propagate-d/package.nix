# Package D: a second direct dependency of A, declaring an env key B also declares. A declares D
# last, so D's value must win (runtime-env launches: last declared direct dependency wins).
{ package }:
package {
  name = "test-propagate-d";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/lib"
        "d" | save -f $"($c.out)/lib/d.txt"
      '';
    }
  ];
  exports = {
    env.PREC_ORDER = "from-d";
  };
  tests.version = false;
}
