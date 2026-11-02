{ package }:
package {
  name = "test-passthrough";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/lib"
        x cc -c p.c -o $"($c.out)/lib/unset.o"
        for v in ["" "0" "false" "off" "true" "yes"] {
          let name = (if $v == "" { "empty" } else { $v })
          with-env {JIG_PASSTHROUGH: $v} { x cc -c p.c -o $"($c.out)/lib/($name).o" }
        }
        with-env {JIG_PASSTHROUGH: "1"} { x cc -c p.c -o $"($c.out)/lib/one.o" }
        # the c++ name under passthrough: still C++, still no policy flags
        with-env {JIG_PASSTHROUGH: "1"} { x c++ -c p.cc -o $"($c.out)/lib/one-cxx.o" }
      '';
    }
  ];
  tests.run = false;
}
