# automake: generates Makefile.in from Makefile.am
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "automake";
  uses = [ "autotools" ];
  patches = [ ./relocatable.patch ];
  # perl scripts that invoke autoconf and m4
  dependencies = [
    pkgs.perl
    pkgs.autoconf
  ];
  buildDependencies = [
    buildPkgs.perl
    buildPkgs.autoconf
  ];
  # the seed's yacc wrapper execs a bison at a placeholder store path ("exec: line 123:
  # /nix/store/eeee…-bison-static-…/bin/bison: not found"), so the 28 yacc tests found a yacc
  # and failed instead of skipping; the seed's toybox tar cannot read the cpio-made ustar
  # archives of `make dist` ("tar: Not tar"), bsdtar can
  tests.dependencies = [
    buildPkgs.bison
    buildPkgs.libarchive
  ];
  # configure says "(cached)" for the testsuite shell but sets AM_TEST_RUNNER_SHELL only when it
  # probes: with a restored config.cache it stayed empty and every test ran `-n` as its shell
  # ("-n: command not found"). A shell named on the command line survives the cache
  autotools.flags = [ "AM_TEST_RUNNER_SHELL=${buildPkgs.bash}/bin/bash" ];
  phases.before."autotools.test" = [
    {
      name = "tests-tools";
      run = ''
        mkdir $"($c.build)/tools"
        ^ln -s (^which bsdtar | str trim) $"($c.build)/tools/tar"
        load-env {PATH: ($env.PATH | prepend $"($c.build)/tools")}
        # objcxx-*: clang has no GNU libobjc: "undefined symbol: __gnu_objc_personality_v0"
        # am-prog-cc-c-o, ccnoco, ccnoco-lib: they run `$CC -v || exit 1`; gcc accepts that,
        # clang links with no input: "ld.lld: error: undefined symbol: main"
        let mk = $"($c.build)/Makefile"
        open --raw $mk | lines | where { |l| $l !~ 't/(objcxx-(minidemo|deps)|am-prog-cc-c-o|ccnoco|ccnoco-lib)[.]sh' } | str join "\n" | $in + "\n" | save -f $mk
      '';
    }
  ];
  bin = [
    "automake"
    "aclocal"
  ];
}
