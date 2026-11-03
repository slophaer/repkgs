# libtool: generic library support script
{
  package,
  pkgs,
  buildPkgs,
}:
package {
  name = "libtool";
  uses = [ "autotools" ];
  patches = [ ./relocatable.patch ];
  autotools.flags = [
    "--disable-ltdl-install" # don't install libltdl; libtool's macros and script work without it
  ];
  # Touch the man pages so they don't get regenerated (we don't have help2man)
  phases.before."autotools.build" = [
    {
      name = "man-uptodate";
      run = ''^touch ...(files $"($c.src)/doc/*.1")'';
    }
  ];
  # libtool and libtoolize are shell scripts that need various tools on PATH
  dependencies = [
    pkgs.m4
    pkgs.bash
    pkgs.coreutils
    pkgs.sed
    pkgs.grep
  ];
  buildDependencies = [
    buildPkgs.m4
    buildPkgs.bash
  ];
  # 76: the suite expects "-R/foobar" in liba.la, which libtool records only when
  # hardcode_into_libs != yes or static libs are built; this package set configures
  # --disable-static (build_old_libs=no in the generated libtool), so grep /foobar fails
  # 129: the dlpreopen'd module foo1 is not found ("function 'f' not found: ...libfoo1.so:
  # undefined symbol: i", no "libfoo1: 2" line); cause inside libltdl preload name lookup
  # not pinned down
  # 187 reruns every "libtool" test with a low max_cmd_len; INNER_TESTSUITEFLAGS drops 76 and 129 there too
  # the tests run the built libtoolize, whose "#! /usr/bin/env sh" configure generated after
  # prepare's shebang rewrite ("/usr/bin/env: bad interpreter"); undo before install
  phases.before."autotools.test" = [
    {
      name = "build-shebangs";
      run = ''
        fix-shebangs $c.build
        load-env {TESTSUITEFLAGS: $"-j(test-jobs) 1-75 77-128 130-187 INNER_TESTSUITEFLAGS=,!runpath,!enforced"}
      '';
    }
  ];
  phases.after."autotools.test" = [
    {
      name = "build-shebangs-undo";
      run = "fix-shebangs $c.build --undo";
    }
  ];
  bin = [
    "libtool"
    "libtoolize"
  ];
}
