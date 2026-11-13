# The package set for one platform and what it is made from:
# { pkgs, platform, buildPkgs, bootstrap, buildSystems, toolchain, variant, extend, sbom, bundle }.
# default.nix is `pkgs` alone; nix/checks.nix reads the rest.
{
  system ? builtins.currentSystem,
  platform ? system,
  seed ? null,
  overrides ? { },
  packages ? { },
  features ? { },
}:
let
  ov = import ./overrides.nix;
  overrideTree = ov.merge overrides;
  feat = import ./features.nix;
  bootstrap = import ../bootstrap { inherit seed system; };

  platforms = import ./platforms.nix;
  target = platforms.byName.${platform} or (throw "no platform ${platform}");
  stage = bootstrap.toolchain.${platform} (
    lib.on (target.libc == "msvc") {
      sdk = fetch.windowsSdk {
        manifest = (readSources ../pkgs/wi/windows-sdk/sources.toml).fetch "default";
        arch = target.cpu;
      };
    }
  );
  inherit (target) os;
  plat = stage.platform // rec {
    inherit system;
    cross = platform != system;
    buildRustTriple = (platforms.forSystem system "glibc").rustTriple;
    # its address cap is $QEMU_RESERVED_VA (builder/prepare.nu), build systems want one word here
    emulator =
      if cross && os == "linux" then
        [ "${buildPkgs.qemu}/bin/qemu-${stage.platform.names.qemu}" ]
      else if cross && os == "windows" && target.cpu == "x86_64" then
        [ "${buildPkgs.wine}/bin/wine" ]
      else
        [ ];
  };
  toolchain = stage.cc;
  inherit (stage) libcOut;
  launch = stage.launch or null;
  dlaudit = stage.dlaudit or null;
  buildPkgs =
    if plat.cross then
      (import ./set.nix {
        platform = system;
        inherit
          seed
          system
          overrides
          packages
          ;
      }).pkgs
    else
      self;

  # build systems that spawn `sh` by name get the seed's dash
  lib = import ./lib.nix;
  inherit (lib) on;
  buildSystems = import ./build-systems.nix {
    inherit buildPkgs fetch lib;
    platform = plat;
    pkgs = self;
    sh = bootstrap.seed;
  };
  # On PATH after the toolchain and the build systems' tools. GNU userland precedes the seed because
  # build scripts in the wild need more than toybox. llvm brings the object tools, the seed bsdtar,
  # nu, sh. `bootstrap` is what the base userland itself is built with (`bootstrapTools = true`).
  baseTools = {
    full =
      (with buildPkgs; [
        coreutils
        sed
        grep
        gawk
        diffutils
        findutils
        patch
        gnumake
        bash
        pkgconf
      ])
      ++ [
        bootstrap.llvm
        bootstrap.seed
      ];
    bootstrap = [
      bootstrap.llvm
      bootstrap.seed
    ];
  };

  # the `package` function under an override tree (the set's, or a variant's on top of it)
  packageFor =
    tree:
    import ./package.nix {
      platform = plat;
      nu = bootstrap.seed;
      inherit lib;
      # `prebuilt = true` patches upstream ELFs with it (builder/implant.nu)
      relocTools = [ buildPkgs.formatelf ];
      inherit
        toolchain
        libcOut
        launch
        dlaudit
        buildSystems
        baseTools
        ;
      # identity when there are none, so the common case allocates nothing per package
      edit = if tree == { } then null else ov.apply self tree;
      # [pin] sys names resolve here
      pkgs = self;
    };
  package = packageFor overrideTree;
  # what callWith edits specs with: the set's own overrides
  setOverrides = {
    tree = overrideTree;
    inherit package;
  };

  fetch = import ./fetch.nix {
    inherit (bootstrap.stage0) jig;
    sevenzip = buildPkgs."7zip";
    nu = bootstrap.seed;
    inherit system;
    inherit (plat) cpu;
  };

  scope = {
    inherit
      package
      fetch
      toolchain
      buildPkgs
      ;
    platform = plat;
    pkgs = self;
    inherit lib on;
    # cpython's package.nix adds .env/.project with this (nix/python.nix)
    pythonProject =
      package: python:
      import ./python.nix {
        inherit
          package
          fetch
          python
          buildPkgs
          ;
        pkgs = self;
      };
  };
  readSources = import ./sources.nix {
    unpacker = bootstrap.seed;
    inherit system;
  };
  # `over`: the override tree and the `package` function made with it (setOverrides, or a
  # set-level variant's)
  callPackageWith =
    over: dir: name:
    let
      st = dir + "/sources.toml";
      sources = if builtins.pathExists st then readSources st else null;
    in
    callWith over (import (dir + "/package.nix")) dir name sources null;
  callPackage = callPackageWith setOverrides;
  # one package.nix evaluated under `name`: `fn` its function, `edit0` what `variant` adds on
  # top of the spec (identity for the package itself). `variant pkgs.llvm { … }` re-enters here
  # with llvm's function, so the base body sees this name's sources and features
  callWith =
    over: fn: dir: name: sources: edit0:
    let
      formals = builtins.functionArgs fn;
      edit = if edit0 == null then (a: a) else edit0;
      local = over.tree.${name}.features or { };
      # default <- set-wide <- overrides.<name>.features, for a package.nix that takes `features`.
      # Its declaration is read by one more call whose `package` just returns it: lazy (no spec
      # is built), and the real call's dependencies may then depend on feature values. One that
      # declares features without reading them only pays when overridden
      resolved =
        if formals ? features || local != { } then
          feat.resolve name
            (fn (
              builtins.intersectAttrs formals (
                scope
                // {
                  inherit sources;
                  features = { };
                  package = a: { decl = (edit a).features or { }; };
                  variant = base: _tree: { inherit (base) decl; };
                }
              )
            )).decl
            features
            local
        else
          { };
      result = fn (
        builtins.intersectAttrs formals (
          scope
          // {
            inherit sources;
            features = resolved;
            package =
              if edit0 == null then
                over.package sources dir resolved fn
              else
                args: over.package sources dir resolved fn (edit0 args);
            # another package's spec under this name, edited with override verbs: this function
            # again with the base's package.nix. Own sources.toml when the directory has one
            # (llvm22: another pin), else the base's (rust-std: same tarball). A list of trees merges
            variant =
              base: tree:
              callWith over base.fn base.dir name (if sources == null then base.sources else sources) (
                args: ov.applyOne self name (ov.merge tree) (edit args // { inherit name; })
              );
          }
        )
      );
    in
    result;

  # pkgs/<first two letters>/<name>/package.nix, attribute name == directory name
  unknownOverrides = ov.unknown (self // aliases) overrideTree;
  # name -> the directory its package.nix is in: the tree, then the out-of-tree packages
  dirs =
    builtins.listToAttrs (
      builtins.concatMap (
        shard:
        let
          dir = ../pkgs + "/${shard}";
        in
        map
          (n: {
            name = n;
            value = dir + "/${n}";
          })
          (
            builtins.filter (n: builtins.pathExists (dir + "/${n}/package.nix")) (
              builtins.attrNames (builtins.readDir dir)
            )
          )
      ) (builtins.attrNames (removeAttrs (builtins.readDir ../pkgs) [ "aliases.toml" ]))
    )
    // packages;
  self = builtins.mapAttrs (n: dir: callPackage dir n) dirs // aliases;

  # pkgs.<name> made again from its package.nix, with `tree` (what `overrides.<name>` takes,
  # `features` too) applied after the set's own overrides. Only this derivation changes: the set
  # and its packages, those that depend on <name> included, keep the original. An alias names
  # its target. For a package nothing else in the set links (a kernel, a data bundle)
  variant =
    name: tree:
    let
      real = aliasTargets.${name} or name;
      merged =
        if overrideTree ? ${real} then
          ov.merge [
            overrideTree.${real}
            tree
          ]
        else
          tree;
      trees = overrideTree // {
        ${real} = merged;
      };
    in
    if !(dirs ? ${real}) then
      throw "variant: no package named ${name}"
    else
      callPackageWith {
        tree = trees;
        package = packageFor trees;
      } dirs.${real} real;

  # this set imported again with more arguments: `overrides` after this set's, `packages` and
  # `features` merged over its own. Every package sees the change, so what depends on a changed
  # package gets a new derivation and the rest keeps its own; evaluation is a fresh import's
  extend =
    more:
    let
      bad = builtins.attrNames (
        removeAttrs more [
          "overrides"
          "packages"
          "features"
        ]
      );
      asList = t: if builtins.isList t then t else [ t ];
    in
    if bad != [ ] then
      throw "extend: ${toString bad}: takes overrides, packages and features; another platform or seed is another import"
    else
      import ./set.nix {
        inherit system platform seed;
        overrides = asList overrides ++ asList (more.overrides or [ ]);
        packages = packages // more.packages or { };
        features = features // more.features or { };
      };
  # unversioned names for the default line of multi-version packages (pkgs/aliases.toml)
  aliasTargets = builtins.fromTOML (builtins.readFile ../pkgs/aliases.toml);
  # aliases go on top of every package, so an out-of-tree one with an alias's name would be dropped
  aliasTaken = builtins.filter (n: aliasTargets ? ${n}) (builtins.attrNames packages);
  aliases = builtins.mapAttrs (
    alias: target:
    if builtins.pathExists (../pkgs + "/${builtins.substring 0 2 alias}/${alias}/package.nix") then
      throw "alias ${alias} shadows a package directory"
    else
      self.${target}
  ) aliasTargets;
in
{
  # attrNames alone would not force the platform: `list --for typo` showed this machine's set
  pkgs = builtins.seq stage (
    if unknownOverrides != [ ] then
      throw "overrides: no packages named ${toString unknownOverrides}"
    else if aliasTaken != [ ] then
      let
        n = builtins.head aliasTaken;
      in
      throw "packages: ${n} is an alias (pkgs/aliases.toml: ${n} -> ${aliasTargets.${n}}), which would hide the package; replace ${aliasTargets.${n}} or choose another name"
    else
      self
  );
  # the elaborated platform record every package receives
  platform = plat;
  inherit variant extend;
  inherit bootstrap buildSystems toolchain;
  # the build host's set: `pkgs` itself when not cross, the host-platform set when cross
  inherit buildPkgs;
  # sbom { roots = [ pkgs.jq ]; name = "jq"; }: CycloneDX 1.5 of the packages' sources (nix/sbom.nix)
  sbom = import ./sbom.nix {
    nu = bootstrap.seed;
    inherit system;
    # the stage's libc has no package.nix; its sources.toml is the record
    libc0 =
      if plat.cross || os != "linux" then
        null
      else
        {
          name = "glibc";
          dir = ../pkgs/gl/glibc;
        };
  };
  bundle = import ./bundle.nix {
    nu = bootstrap.seed;
    tools = [ buildPkgs.formatelf ] ++ baseTools.bootstrap;
    tree = ../builder;
  };
}
