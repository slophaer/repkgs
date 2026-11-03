# Package B: links C, propagates C to dependents
{ package, pkgs }:
package {
  name = "test-propagate-b";
  version = "1";
  source = ./src;
  dependencies = [ pkgs.test-propagate-c ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/lib" $"($c.out)/include"
        let c_root = (dep-root "test-propagate-c" "link against C")
        x cc -shared -fPIC lib.c $"-I($c_root)/include" $"-L($c_root)/lib" -lc_propagate -o $"($c.out)/lib/libb_propagate.so"
        cp b.h $"($c.out)/include/"
      '';
    }
  ];
  exports = {
    propagate = [ pkgs.test-propagate-c ];
    env.B_MARKER = "from-b";
    # the same key C exports (propagated): the direct dependency must win
    env.PREC_DIRECT = "from-b";
    # the same key D exports (direct): the last declared direct dependency must win
    env.PREC_ORDER = "from-b";
  };
  tests.version = false;
}
