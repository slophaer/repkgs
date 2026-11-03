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
  # the value of each golconda:approximation property of a component
  approx =
    c: map (p: p.value) (builtins.filter (p: p.name == "golconda:approximation") (c.properties or [ ]));
  has = re: c: builtins.any (v: match re v != null) (approx c);
  depsOf = b: ref: (builtins.head (builtins.filter (d: d.ref == ref) b.dependencies)).dependsOn;

  # a wrapper stands in for jq: it is its own component, and jq's graph hangs off it
  wrapped = set.wrap { package = set.pkgs.jq; };
  wbom =
    (set.sbom {
      roots = [ wrapped ];
      name = "jq-wrap";
    }).bom;
  wroot = builtins.head (builtins.head wbom.dependencies).dependsOn;
  wjq = builtins.head (builtins.filter (c: c.name == "jq" && c ? purl) wbom.components);

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

  # The hook receives original packages, even wrappers and metadata-free records.
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
  roots = [
    set.pkgs.jq
    wrapped
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
  p: p.name == "golconda:approximation" && match ".*buildDependencies.*" p.value != null
) (bom.metadata.properties or [ ]);
assert
  bzip2.purl == "pkg:generic/bzip2@${set.pkgs.bzip2.version}" && has ".*query.*dropped.*" bzip2;
assert !(has ".*query.*" (byName "jq"));
# a wrapper: its own component over the wrapped graph
assert uniqueRefs wbom;
assert elem "oniguruma" (map (c: c.name) wbom.components);
assert depsOf wbom wroot == [ wjq.bom-ref ];
assert wroot != wjq.bom-ref;
# same-name variants stay apart
assert builtins.length onigs == 2 && uniqueRefs vbom;
# Default and empty hooks retain current properties and omit an empty property list.
assert empty.bom == plain.bom;
assert empty.drvPath == plain.drvPath;
assert !((componentAt plain.bom (rootRef 5)) ? properties);
assert !((componentAt empty.bom (rootRef 5)) ? properties);
# Append after each component's full baseline list, including every approximation marker.
assert appended set.pkgs.jq (rootRef 0);
assert appended wrapped (rootRef 1);
assert appended set2.pkgs.oniguruma (rootRef 2);
assert appended set.pkgs.bzip2 (rootRef 3);
assert appended unrecorded (rootRef 4);
assert appended unmarked (rootRef 5);
assert appended set.pkgs.oniguruma onigRef;
assert appended {
  name = "glibc";
  dir = ../pkgs/gl/glibc;
} libcRef;
# Same-name derivations keep separate refs and receive their own callback results.
assert uniqueRefs hooked.bom;
assert (rootRef 2) != onigRef;
assert set.pkgs.oniguruma.drvPath != set2.pkgs.oniguruma.drvPath;
assert callbackDrv (rootRef 2) != callbackDrv onigRef;
assert callbackDrv (rootRef 1) != callbackDrv (rootRef 0);
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
assert depsOf hooked.bom (rootRef 1) == [ (rootRef 0) ];
assert depsOf hooked.bom (rootRef 2) == [ libcRef ];
assert depsOf hooked.bom (rootRef 3) == [ libcRef ];
assert
  depsOf hooked.bom (rootRef 4) == [
    libcRef
    (rootRef 0)
  ];
assert depsOf hooked.bom (rootRef 5) == [ libcRef ];
assert depsOf hooked.bom onigRef == [ libcRef ];
assert depsOf hooked.bom libcRef == [ ];
hooked
