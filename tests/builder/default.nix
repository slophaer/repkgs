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
      # wrap with files, an argv prefix and env; apostrophes must pass through unchanged
      if name == "wrap-files" then
        {
          wrapped = set.wrap {
            package = set.pkgs.test-wrap-files;
            files."a.conf" = "hello";
            files."it's.conf" = "say 'hi'\n";
            argv = [
              "--conf"
              "{root}/share/wrap/test-wrap-files/a.conf"
              "it's"
            ];
            env.OUTER.set = "o'k";
          };
        }
      else
        { }
    )
    // (
      # a wrapper over packages whose bin/ entries have launch records of their own
      if name == "wrap-chain" then
        let
          inner = set.pkgs.test-wrap-files;
          wrapped = set.wrap {
            package = inner;
            argv = [ "--outer" ];
            env.OUTER.set = "outer";
          };
        in
        {
          inherit wrapped;
          wrappedBin = builtins.toJSON (wrapped.bin or null);
          innerBin = builtins.toJSON inner.bin;
        }
      else
        { }
    )
    // (
      # declared executables (pkg.bin, at evaluation) against what bin/ holds (exports.json)
      if name == "bin" then
        let
          inherit (set.pkgs) jq zlib;
          wrapped = set.wrap { package = jq; };
        in
        assert set.pkgs.oniguruma.bin == [ "onig-config" ];
        assert set.pkgs.test-tz.bin == [ "tz" ];
        assert set.pkgs.test-tz.args.tests.version == false;
        {
          inherit jq wrapped;
          jqBin = builtins.toJSON jq.bin;
          zlibBin = builtins.toJSON zlib.bin;
          wrappedBin = builtins.toJSON (wrapped.bin or null);
        }
      else
        { }
    )
    // (
      if name == "prefix" then
        assert (set.pkgs.wine.args.prefix or null) == "/usr";
        assert !(builtins.elem "--prefix=/usr" set.pkgs.wine.args.autotools.flags);
        assert !(builtins.elem "prefix=$(out)" (set.pkgs.wine.args.autotools.installFlags or [ ]));
        { }
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
    // (
      if
        builtins.elem name [
          "sysroot"
          "unwinder"
          "glibc-prefix-map"
        ]
      then
        {
          sysrootRecipe = ../../bootstrap/sysroot.nu;
          glibcRecipe = ../../pkgs/gl/glibc/bootstrap.nu;
          bootstrapLib = ../../bootstrap/lib.nu;
          bootstrapGlob = ../../builder/glob.nu;
          bootstrapLog = ../../builder/log.nu;
        }
      else
        { }
    )
  )
) tests
