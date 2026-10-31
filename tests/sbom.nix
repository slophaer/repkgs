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
jq
