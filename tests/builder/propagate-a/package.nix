# Package A: links B only, should get C's env through B's propagate
{ package, pkgs }:
package {
  name = "test-propagate-a";
  version = "1";
  source = ./src;
  dependencies = [
    pkgs.test-propagate-b
    pkgs.test-propagate-d
  ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin"
        let b_root = (dep-root "test-propagate-b" "link against B")
        let c_root = (dep-root "test-propagate-c" "link against C (propagated)")
        x cc main.c $"-I($b_root)/include" $"-I($c_root)/include" $"-L($b_root)/lib" $"-L($c_root)/lib" -lb_propagate -lc_propagate -o $"($c.out)/bin/test-propagate-a"
      '';
    }
  ];
  tests.version = false;
}
