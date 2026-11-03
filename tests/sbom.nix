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

  # No directory metadata: the hook must still receive the original package.
  unrecorded = {
    name = "unrecorded";
    dependencies = [ set.pkgs.jq ];
  };
  roots = [
    set.pkgs.jq
    unrecorded
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
  ];
  hooked = set.sbom {
    inherit roots;
    name = "properties";
    extraProperties = propertiesFor;
  };
  componentIn = b: n: builtins.head (builtins.filter (c: c.name == n) b.components);
  approximation = [
    {
      name = "golconda:approximation";
      value = "no sources.toml purl: name from the derivation, no purl";
    }
  ];
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
# A default or empty hook must not change the BOM or add empty properties.
assert all (c: !(c ? properties)) bom.components;
assert empty.bom == plain.bom;
assert empty.drvPath == plain.drvPath;
assert (componentIn plain.bom "unrecorded").properties == approximation;
# Roots, transitive packages and the implicit libc all receive their package's properties.
assert (componentIn hooked.bom "jq").properties == propertiesFor set.pkgs.jq;
assert (componentIn hooked.bom "oniguruma").properties == propertiesFor set.pkgs.oniguruma;
assert
  (componentIn hooked.bom "glibc").properties == propertiesFor {
    name = "glibc";
    dir = ../pkgs/gl/glibc;
  };
assert
  (componentIn hooked.bom "unrecorded").properties == approximation ++ propertiesFor unrecorded;
# Only the properties change, not component metadata, ordering, or the dependency graph.
assert
  hooked.bom == plain.bom
  // {
    components = map (
      c: c // { inherit (componentIn hooked.bom c.name) properties; }
    ) plain.bom.components;
  };
hooked
