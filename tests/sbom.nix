# nix/sbom.nix: the CycloneDX shape and jq's closure, asserted at evaluation, then the file built.
#   nix-build tests/sbom.nix        (the output is the sbom.json directory)
{
  system ? builtins.currentSystem,
}:
let
  set = import ../nix/set.nix { inherit system; };
  inherit (builtins)
    all
    elem
    isString
    match
    ;
  jq = set.sbom {
    roots = [ set.pkgs.jq ];
    name = "jq";
  };
  inherit (jq) bom;
  names = map (c: c.name) bom.components;
  byName = n: builtins.head (builtins.filter (c: c.name == n) bom.components);
  hex = h: match "[0-9a-f]{64}" h != null;
  shaped =
    c:
    isString c.name
    && elem c.type [
      "application"
      "library"
    ]
    && isString c.version
    && match "pkg:[a-z]+/.+@.+" c.purl != null
    && all (h: h.alg == "SHA-256" && hex h.content) c.hashes
    && c.hashes != [ ];
  refs = map (c: c.bom-ref) bom.components;
  graphOk = all (d: all (r: elem r refs) d.dependsOn) (builtins.tail bom.dependencies);
  uniqueRefs =
    b:
    let
      r = map (c: c.bom-ref) b.components;
    in
    builtins.length r == builtins.length (builtins.attrNames (builtins.groupBy (x: x) r));
  # the value of each repkgs:approximation property of a component
  approx =
    c: map (p: p.value) (builtins.filter (p: p.name == "repkgs:approximation") (c.properties or [ ]));
  has = re: c: builtins.any (v: match re v != null) (approx c);
  depsOf = b: ref: (builtins.head (builtins.filter (d: d.ref == ref) b.dependencies)).dependsOn;

  # the same name and version, another spec: two components, two refs
  set2 = import ../nix/set.nix {
    inherit system;
    overrides.oniguruma.autotools.flags.append = [ "--disable-posix-api" ];
  };
  vbom =
    (set.sbom {
      roots = [
        set.pkgs.jq
        set2.pkgs.oniguruma
      ];
    }).bom;
  onigs = builtins.filter (c: c.name == "oniguruma") vbom.components;

  bzip2 = builtins.head (set.sbom { roots = [ set.pkgs.bzip2 ]; }).bom.components;

  # The hook receives original packages, even metadata-free records.
  unrecorded = {
    name = "unrecorded";
    dependencies = [ set.pkgs.jq ];
  };
  # Known source metadata without a hash or query needs no approximation property.
  unmarked = {
    name = "unmarked";
    pname = "unmarked";
    inherit (set.pkgs.jq) dir version;
    dependencies = [ ];
  };
  # A CPE template in sources.toml becomes the component's cpe, the version filled in.
  withcpe = {
    name = "withcpe-1.2";
    pname = "withcpe";
    version = "1.2";
    dir = ./sbom-fixtures/withcpe;
    dependencies = [ ];
  };
  cpeBom =
    (set.sbom {
      roots = [
        withcpe
        set.pkgs.jq
      ];
      name = "cpe";
    }).bom;
  cpeOf = n: (builtins.head (builtins.filter (c: c.name == n) cpeBom.components)).cpe or null;
  # extraFields adds whole fields (here CycloneDX pedigree) to a component; it may not replace one
  # the generator sets.
  pedigree = {
    ancestors = [
      {
        type = "library";
        name = "jq";
        version = "0";
      }
    ];
    notes = "test";
  };
  fielded =
    (set.sbom {
      roots = [ set.pkgs.jq ];
      name = "fields";
      extraFields = p: if (p.pname or null) == "jq" then { inherit pedigree; } else { };
    }).bom;
  fieldedAt = n: builtins.head (builtins.filter (c: c.name == n) fielded.components);
  replacing =
    field:
    !(builtins.tryEval (
      builtins.deepSeq
        (set.sbom {
          roots = [ set.pkgs.jq ];
          name = "replacing";
          extraFields = _: { ${field} = "x"; };
        }).bom.components
        true
    )).success;
  roots = [
    set.pkgs.jq
    set2.pkgs.oniguruma
    set.pkgs.bzip2
    unrecorded
    unmarked
  ];
  plain = set.sbom {
    inherit roots;
    name = "properties";
  };
  empty = set.sbom {
    inherit roots;
    name = "properties";
    extraProperties = _: [ ];
  };
  propertiesFor = p: [
    {
      name = "test:package";
      value = p.name;
    }
    {
      name = "test:directory";
      value = if p ? dir then "present" else "absent";
    }
    {
      name = "test:drv";
      value = builtins.unsafeDiscardStringContext (p.drvPath or "none");
    }
  ];
  hooked = set.sbom {
    inherit roots;
    name = "properties";
    extraProperties = propertiesFor;
  };
  componentAt = b: ref: builtins.head (builtins.filter (c: c.bom-ref == ref) b.components);
  rootRefs = (builtins.head plain.bom.dependencies).dependsOn;
  rootRef = builtins.elemAt rootRefs;
  libcRef = (builtins.head (builtins.filter (c: c.name == "glibc") plain.bom.components)).bom-ref;
  onigRef =
    (builtins.head (
      builtins.filter (c: c.name == "oniguruma" && c.type == "library") plain.bom.components
    )).bom-ref;
  appended =
    p: ref:
    (componentAt hooked.bom ref).properties
    == ((componentAt plain.bom ref).properties or [ ]) ++ propertiesFor p;
  # pedigree.patches: each patch's type, link and text, from the file alone
  fixture = f: ./sbom-fixtures/patched + "/${f}";
  patchFiles = [
    "bare.patch"
    "own-format-patch.patch"
    "cherry-picked.patch"
    "origin-upstream.patch"
    "origin-url.patch"
  ];
  patched = {
    name = "patched-2.0";
    pname = "patched";
    version = "2.0";
    dir = ./sbom-fixtures/patched;
    # a fetched patch is a store path, not read at evaluation
    patches = map fixture patchFiles ++ [ (builtins.toFile "fetched.patch" "") ];
    dependencies = [ ];
  };
  componentOf =
    args: n: builtins.head (builtins.filter (c: c.name == n) (set.sbom args).bom.components);
  patchesOf = (componentOf { roots = [ patched ]; } "patched").pedigree.patches;
  patchAt = builtins.elemAt patchesOf;
  withPedigree =
    pedigree:
    componentOf {
      roots = [ patched ];
      extraFields = _: { inherit pedigree; };
    } "patched";

  # sourceOf and upstream, on records and through package.nix
  derived = {
    name = "derived-1";
    pname = "derived";
    version = "1";
    sourceOf = {
      package = set.pkgs.jq;
      subpath = "src/x";
    };
    dependencies = [ ];
  };
  derivedTwice = {
    name = "twice-1";
    pname = "twice";
    version = "1";
    sourceOf = {
      package = derived;
      subpath = "y";
    };
    dependencies = [ ];
  };
  fromCpe = {
    name = "fromcpe-1";
    pname = "fromcpe";
    version = "1";
    sourceOf.package = withcpe;
    dependencies = [ ];
  };
  jqPurl = (byName "jq").purl;
  local = setWith {
    packages = {
      sbom-derived = ./sbom-fixtures/derived;
      sbom-upstream = ./sbom-fixtures/upstream;
    };
  };
  setWith = args: import ../nix/set.nix ({ inherit system; } // args);
  localComponent = n: componentOf { roots = [ local.pkgs.${n} ]; } n;
  refused =
    overrides:
    !(builtins.tryEval (
      builtins.deepSeq
        (setWith {
          packages.sbom-upstream = ./sbom-fixtures/upstream;
          inherit overrides;
        }).pkgs.sbom-upstream.drvPath
        true
    )).success;

  refusedSourceOf =
    o:
    refused {
      sbom-upstream = {
        upstream.remove = true;
        sourceOf.set = o;
      };
    };

  callbackDrv =
    ref:
    (builtins.head (builtins.filter (p: p.name == "test:drv") (componentAt hooked.bom ref).properties))
    .value;
in
assert bom.bomFormat == "CycloneDX";
assert bom.specVersion == "1.5";
assert
  names == [
    "glibc"
    "jq"
    "oniguruma"
  ];
assert all shaped bom.components;
assert (byName "jq").purl == "pkg:github/jqlang/jq@jq-${set.pkgs.jq.version}";
assert (byName "oniguruma").purl == "pkg:github/kkos/oniguruma@v6.9.10";
assert (byName "glibc").purl == "pkg:gnu/glibc@${(byName "glibc").version}";
# every edge points at a listed component, and the roots hang off the document
assert graphOk;
assert (builtins.head bom.dependencies).dependsOn == [ (byName "jq").bom-ref ];
# the second pass must not add a component twice
assert
  (set.sbom {
    roots = [
      set.pkgs.jq
      set.pkgs.jq
      set.pkgs.oniguruma
    ];
  }).bom.components != [ ]
  &&
    map (c: c.name)
      (set.sbom {
        roots = [
          set.pkgs.jq
          set.pkgs.oniguruma
        ];
      }).bom.components == names;
# every approximation the header names is marked where it applies
assert all (has "sha256 of the unpacked source.*") (builtins.filter (c: c ? hashes) bom.components);
assert has ".*implicit.*" (byName "glibc");
assert builtins.any (
  p: p.name == "repkgs:approximation" && match ".*buildDependencies.*" p.value != null
) (bom.metadata.properties or [ ]);
assert
  bzip2.purl == "pkg:generic/bzip2@${set.pkgs.bzip2.version}" && has ".*query.*dropped.*" bzip2;
assert !(has ".*query.*" (byName "jq"));
# same-name variants stay apart
assert builtins.length onigs == 2 && uniqueRefs vbom;
# A CPE template becomes the cpe with the version; no template, no cpe.
assert cpeOf "withcpe" == "cpe:2.3:a:example:withcpe:1.2:*:*:*:*:*:*:*";
assert cpeOf "jq" == null;
# extraFields adds a field to the components it returns one for, and nothing else changes.
assert (fieldedAt "jq").pedigree == pedigree;
assert !((fieldedAt "oniguruma") ? pedigree);
assert
  fielded == (set.sbom {
    roots = [ set.pkgs.jq ];
    name = "fields";
  }).bom
  // {
    components =
      map (c: if c.name == "jq" then c // { inherit pedigree; } else c)
        (set.sbom {
          roots = [ set.pkgs.jq ];
          name = "fields";
        }).bom.components;
  };
# a field the generator sets cannot be replaced, properties included (extraProperties appends)
assert replacing "purl";
assert replacing "bom-ref";
assert replacing "properties";
# Default and empty hooks retain current properties and omit an empty property list.
assert empty.bom == plain.bom;
assert empty.drvPath == plain.drvPath;
assert !((componentAt plain.bom (rootRef 4)) ? properties);
assert !((componentAt empty.bom (rootRef 4)) ? properties);
# Append after each component's full baseline list, including every approximation marker.
assert appended set.pkgs.jq (rootRef 0);
assert appended set2.pkgs.oniguruma (rootRef 1);
assert appended set.pkgs.bzip2 (rootRef 2);
assert appended unrecorded (rootRef 3);
assert appended unmarked (rootRef 4);
assert appended set.pkgs.oniguruma onigRef;
assert appended {
  name = "glibc";
  dir = ../pkgs/gl/glibc;
} libcRef;
# Same-name derivations keep separate refs and receive their own callback results.
assert uniqueRefs hooked.bom;
assert (rootRef 1) != onigRef;
assert set.pkgs.oniguruma.drvPath != set2.pkgs.oniguruma.drvPath;
assert callbackDrv (rootRef 1) != callbackDrv onigRef;
# The hook must not change metadata, component order, identity, or dependency edges.
assert
  hooked.bom == plain.bom
  // {
    components = map (
      c: c // { inherit (componentAt hooked.bom c.bom-ref) properties; }
    ) plain.bom.components;
  };
# Check concrete edges too: losing the same edges in both BOM modes must fail.
assert
  depsOf hooked.bom (rootRef 0) == [
    libcRef
    onigRef
  ];
assert depsOf hooked.bom (rootRef 1) == [ libcRef ];
assert depsOf hooked.bom (rootRef 2) == [ libcRef ];
assert
  depsOf hooked.bom (rootRef 3) == [
    libcRef
    (rootRef 0)
  ];
assert depsOf hooked.bom (rootRef 4) == [ libcRef ];
assert depsOf hooked.bom onigRef == [ libcRef ];
assert depsOf hooked.bom libcRef == [ ];

# A patch is a backport only when it says so; format-patch's From line alone does not
assert
  map (p: p.type) patchesOf == [
    "unofficial"
    "unofficial"
    "backport"
    "backport"
    "backport"
    "unofficial"
  ];
assert
  map (p: p.diff.url) patchesOf == [
    "bare.patch"
    "own-format-patch.patch"
    "https://github.com/example/patched/commit/3333333333333333333333333333333333333333"
    "https://github.com/example/patched/commit/4444444444444444444444444444444444444444"
    "https://gitlab.example.org/team/patched/-/commit/5555555"
    "fetched.patch"
  ];
assert
  (patchAt 0).diff.text == {
    contentType = "text/x-diff";
    content = builtins.readFile (fixture "bare.patch");
  };
assert !((patchAt 0) ? resolves) && !((patchAt 5).diff ? text);
assert
  (patchAt 1).resolves == [
    {
      type = "defect";
      name = "build: fix the install of the frobnicator";
      references = [ "https://example.org/bugs/1" ];
    }
  ];
# the backport markers' links are the commit, not an issue
assert
  (patchAt 4).resolves == [
    {
      type = "enhancement";
      name = "take the fix for the parser";
      references = [ "https://example.org/bugs/5" ];
    }
  ];
assert !((byName "jq") ? pedigree);
# a caller's pedigree goes over the generator's by key
assert
  (withPedigree { notes = "n"; }).pedigree == {
    patches = patchesOf;
    notes = "n";
  };
assert (withPedigree { patches = [ ]; }).pedigree == { patches = [ ]; };

# sourceOf: the source package's purl and hash, a subpath, no cpe
assert (componentOf { roots = [ derived ]; } "derived").purl == "${jqPurl}#src/x";
assert (componentOf { roots = [ derived ]; } "derived").hashes == (byName "jq").hashes;
assert (componentOf { roots = [ derived ]; } "derived").version == "1";
assert (componentOf { roots = [ derivedTwice ]; } "twice").purl == "${jqPurl}#src/x/y";
assert
  (componentOf { roots = [ fromCpe ]; } "fromcpe").purl == "pkg:generic/withcpe@1.2"
  && !((componentOf { roots = [ fromCpe ]; } "fromcpe") ? cpe);
# package.nix takes both, keeps them out of the derivation and exposes them
assert local.pkgs.sbom-derived.sourceOf.package.pname == "jq";
assert !(local.pkgs.sbom-derived.spec ? sourceOf) && !(local.pkgs.sbom-upstream.spec ? upstream);
assert (localComponent "sbom-derived").purl == "${jqPurl}#src";
assert (localComponent "sbom-upstream").purl == "pkg:generic/sbom-upstream@3";
assert (localComponent "sbom-upstream").cpe == "cpe:2.3:a:example:sbom-upstream:3:*:*:*:*:*:*:*";
# and refuses what the generator could not read
assert refused { sbom-upstream.upstream.set.cpe = "x"; };
assert refused { sbom-upstream.upstream.set = "pkg:generic/x"; };
# sourceOf in place of upstream: a package is required, the subpath relative
assert refusedSourceOf { subpath = "x"; };
assert refusedSourceOf {
  package = set.pkgs.jq;
  subpath = "../x";
};
assert
  !(refusedSourceOf {
    package = set.pkgs.jq;
    subpath = "x/y";
  });
# one source: not both, and not beside a sources.toml
assert refused { sbom-upstream.sourceOf.set.package = set.pkgs.jq; };
assert
  !(builtins.tryEval (
    builtins.deepSeq (setWith { overrides.jq.upstream.set.purl = "pkg:generic/x"; }).pkgs.jq.drvPath
      true
  )).success;
hooked
