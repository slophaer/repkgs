# bin/args and bin/greet run through launch records of their own: a wrapper must keep them
{ package }:
package {
  name = "test-wrap-files";
  version = "1";
  source = ./src;
  bin = [
    "args"
    "greet"
  ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/bin" $"($c.out)/share/data" $"($c.out)/libexec"
        x cc args.c -o $"($c.out)/bin/.args"
        write-launcher args $"($c.out)/bin/.args" [--inner] {INNER: inner}
        cp greet.sh $"($c.out)/libexec/greet.sh"
        write-launcher greet /bin/sh [$"($c.out)/libexec/greet.sh"]
        "docs\n" | save -f $"($c.out)/share/data/README"
      '';
    }
  ];
  tests.run = false;
  tests.version = false;
}
