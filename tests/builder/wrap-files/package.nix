{ package }:
package {
  name = "test-wrap-files";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin" $"($c.out)/share/data"
        x cc args.c -o $"($c.out)/bin/args"
        "docs\n" | save -f $"($c.out)/share/data/README"
      '';
    }
  ];
  tests.run = false;
}
