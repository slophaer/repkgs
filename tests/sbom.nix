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
# a wrapper: its own component over the wrapped graph
assert uniqueRefs wbom;
assert elem "oniguruma" (map (c: c.name) wbom.components);
assert depsOf wbom wroot == [ wjq.bom-ref ];
assert wroot != wjq.bom-ref;
# same-name variants stay apart
assert builtins.length onigs == 2 && uniqueRefs vbom;
jq
