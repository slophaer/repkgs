# Builder behaviour: every directory here is a test. Its test.nu runs under the seed's nu with
# builder/ and lib/ on the include path and $env.fixtures set to the directory. One with a
# package.nix is first built as out-of-tree package test-<name> ($env.pkg, $env.debug), so each test
# needs only its own toolchain. `nix-build tests/builder -A <name>`, `repkgs test` for all.
{
  system ? builtins.currentSystem,
  platform ? system,
}:
let
  inherit (builtins)
    readDir
    mapAttrs
    pathExists
    removeAttrs
    attrNames
    filter
    listToAttrs
    ;
  dirs = removeAttrs (readDir ./.) [
    "lib"
    "default.nix"
  ];
  tests = mapAttrs (n: _: ./. + "/${n}") dirs;
  isPackage = n: pathExists (tests.${n} + "/package.nix");
  # as test-<name>: a bare `go` would replace the set's go, which the go build system runs
  set = import ../../nix/set.nix {
    inherit system platform;
    packages = listToAttrs (
      map (n: {
        name = "test-${n}";
        value = tests.${n};
      }) (filter isPackage (attrNames tests))
    );
  };
  seed = set.bootstrap.seed;
in
mapAttrs (
  name: dir:
  derivation (
    {
      name = "check-${name}";
      inherit system;
      __contentAddressed = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      PATH = "${seed}/bin";
      fixtures = dir;
      builder = "${seed}/bin/nu";
      # nu separates include dirs with \x1e
      args = [
        "--no-config-file"
        "--include-path=${../../builder}${builtins.fromJSON "\"\\u001e\""}${./lib}"
        "${dir}/test.nu"
      ];
    }
    // (
      if isPackage name then
        rec {
          pkg = set.pkgs."test-${name}";
          inherit (pkg) debug;
          src = "${dir}/src";
        }
      else
        { }
    )
    // (
      # nix/wrap.nix: the wrapped output's name carries the version, `wraps` names the package
      if name == "wrap" then
        let
          inner = set.pkgs.test-tz;
          wrapped = set.wrap { package = inner; };
        in
        assert wrapped.wraps == inner && wrapped.version == inner.version && wrapped.pname == inner.pname;
        {
          inherit wrapped;
          wrappedName = wrapped.name;
          wrappedWant = "${inner.pname}-${inner.version}-wrap";
        }
      else
        { }
    )
    // (
      # wrap with files and an argv prefix; the file is `"hello"` (files are JSON-encoded)
      if name == "wrap-files" then
        let
          inner = set.pkgs.test-wrap-files;
          wrapped = set.wrap {
            package = inner;
            files."a.conf" = "hello";
            argv = [
              "--conf"
              "{root}/share/wrap/test-wrap-files/a.conf"
            ];
          };
        in
        {
          inherit wrapped;
        }
      else
        { }
    )
    // (
      # nix/closure.nix: jq's closure as a tarball
      if name == "closure" then
        {
          tarball = set.closure {
            roots = [ set.pkgs.jq ];
            name = "jq";
          };
        }
      else
        { }
    )
  )
) tests
