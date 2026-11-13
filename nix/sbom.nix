# A CycloneDX 1.5 SBOM for the runtime closure of some packages, from evaluation alone (no IFD).
#   sbom { roots = [ pkgs.jq ]; name = "jq"; }   a derivation whose output has sbom.json
# The closure is the `dependencies` graph of the packages (the attribute nix/package.nix hands to
# the derivation: package.nix's own list plus [pin] sys libraries and the build systems'), not the
# store references. Version, purl and source hash come from each package's directory:
# `dir`/sources.toml `[upstream] purl`, the pinned version (`version`) and the source fetch's
# `outputHash` (`src`). A package without sources.toml says it in package.nix: `upstream = {
# purl; cpe?; }` for its own source, or `sourceOf = { package; subpath?; }` when it is built from
# another package's source; it then gets that package's purl, plus `#<subpath>`, and source hash,
# and no cpe (it is not that project's product). `libc0` ({ name, dir } or null) is implicit in
# every ELF link and a bootstrap stage with no package of its own, so it joins as a component read
# from its directory's sources.toml, and in the dependsOn of each other one.
# A component is one derivation: two of the same name and version (variants, two sets) stay two.
# Their bom-refs, <name>@<version>, get #<drv hash prefix> appended when they would collide.
#
# A `cpe` in `[upstream]` becomes the component's `cpe`, `{version}` replaced by the version
# (nixpkgs' meta.identifiers.cpe is the model).
#
# A package's `patches` become `pedigree.patches` (nix/sbom-patches.nix): the whole text of each,
# "backport" with the upstream commit when the patch says it is one, else "unofficial".
#
# Callers add to a component with two hooks: `extraProperties p` returns properties appended to
# its own, and `extraFields p` returns whole CycloneDX fields (`pedigree`, `supplier`, …) merged
# in. A field the generator sets (type, bom-ref, name, version, purl, cpe, hashes, properties)
# cannot be replaced: that fails, so a hook cannot change a component's identity. A `pedigree`
# from the hook is merged over the generator's by key (its `patches` replace the generator's).
#
# Approximations, each marked with a `repkgs:approximation` property:
#  - a derivation without `dir` (toolchain, bootstrap stages, seed) has no
#    sources.toml: name and version only, no purl, no hash
#  - hashes are SHA-256 of the unpacked source tree (the NAR hash of what the fetch yields), not
#    of the upstream tarball
#  - a purl's query (uptrack's `?url=…&regex=…` of pkg:generic) is dropped
#  - libc's edges are inferred, not declared
#  - on the document: build-only tools (`buildDependencies`) are left out on purpose, they are
#    not in the runtime closure
{
  nu,
  system,
  libc0 ? null,
}:
{
  roots,
  name ? "sbom",
  # Additional CycloneDX properties for each package in the runtime closure.
  extraProperties ? (_pkg: [ ]),
  # Additional CycloneDX fields for each package in the runtime closure (not the generator's own).
  extraFields ? (_pkg: { }),
}:
let
  inherit (builtins)
    baseNameOf
    convertHash
    elemAt
    filter
    fromTOML
    genericClosure
    groupBy
    head
    length
    match
    pathExists
    readFile
    sort
    split
    substring
    toJSON
    unsafeDiscardStringContext
    ;

  # a stand-in package for the libc stage, from its sources.toml
  libc =
    if libc0 == null then
      null
    else
      let
        t = fromTOML (readFile (libc0.dir + "/sources.toml"));
      in
      {
        inherit (libc0) name dir;
        pname = libc0.name;
        version = t.pin.version;
        src.outputHash = (head t.source).hash;
        dependencies = [ ];
      };

  # one derivation, one component; the libc stand-in is no derivation
  key = p: if p ? drvPath then unsafeDiscardStringContext p.drvPath else p.name;
  # `dependencies` of a package; anything else has none
  depsOf = p: p.dependencies or (p.args.dependencies or [ ]);
  withLibc = if libc == null then roots else roots ++ [ libc ];
  closure = genericClosure {
    startSet = map (p: {
      key = key p;
      inherit p;
    }) withLibc;
    operator =
      n:
      map (d: {
        key = key d;
        p = d;
      }) (depsOf n.p);
  };
  pkgsOf = map (n: n.p) closure;

  # sources.toml, or package.nix's `upstream` as its [upstream] table
  tomlOf =
    p:
    if p ? dir && pathExists (p.dir + "/sources.toml") then
      fromTOML (readFile (p.dir + "/sources.toml"))
    else if p ? upstream then
      { inherit (p) upstream; }
    else
      null;

  # the package whose source this one is built from, its record, and the purl subpath into it
  originOf =
    p:
    if p ? sourceOf then
      let
        o = originOf p.sourceOf.package;
        sub = p.sourceOf.subpath or null;
      in
      o
      // {
        subpath =
          if sub == null then
            o.subpath
          else if o.subpath == null then
            sub
          else
            "${o.subpath}/${sub}";
      }
    else
      {
        pkg = p;
        toml = tomlOf p;
        subpath = null;
      };

  patches = import ./sbom-patches.nix;

  # pkg:github/jqlang/jq?x=y -> pkg:github/jqlang/jq@v1.8.1
  purlOf =
    p: t:
    let
      base = head (split "\\?" t.upstream.purl);
      type = elemAt (match "pkg:([a-z]+)/.*" base) 0;
      pin = t.pin or { };
      v = if type == "github" || type == "gitlab" then pin.tag or p.version else p.version;
    in
    "${base}@${v}";

  # sha256-<base64> of the source fetch -> {alg, content hex}; a local source has no outputHash
  hashesOf =
    p:
    let
      h = (p.src or { }).outputHash or null;
    in
    if h == null || match "sha256-.*" h == null then
      [ ]
    else
      [
        {
          alg = "SHA-256";
          content = convertHash {
            hash = h;
            toHashFormat = "base16";
          };
        }
      ];

  isLibc = p: libc != null && key p == key libc;
  baseRef = p: if p ? version then "${p.pname or p.name}@${p.version}" else p.name;
  byRef = groupBy baseRef pkgsOf;
  ref =
    p:
    let
      b = baseRef p;
    in
    if length byRef.${b} > 1 then "${b}#${substring 0 8 (baseNameOf (key p))}" else b;
  approximation = value: {
    name = "repkgs:approximation";
    inherit value;
  };

  # the caller's fields, after a check that none replaces one of the generator's
  ownFields = [
    "type"
    "bom-ref"
    "name"
    "version"
    "purl"
    "cpe"
    "hashes"
    "properties"
  ];
  withFields =
    p: c:
    let
      extra = extraFields p;
      clash = builtins.filter (f: builtins.elem f ownFields) (builtins.attrNames extra);
    in
    if clash == [ ] then
      c
      // extra
      // (if c ? pedigree && extra ? pedigree then { pedigree = c.pedigree // extra.pedigree; } else { })
    else
      throw "sbom: extraFields for ${p.name} sets ${builtins.concatStringsSep ", " clash}, a field the generator owns; use extraProperties for properties";

  component =
    p:
    let
      o = originOf p;
      t = o.toml;
      known = t != null && t ? upstream.purl && o.pkg ? version;
      purl = purlOf o.pkg t + (if o.subpath == null then "" else "#${o.subpath}");
      hashes = if t == null then [ ] else hashesOf o.pkg;
      cpe =
        if !(p ? sourceOf) && t != null && t ? upstream.cpe && p ? version then
          builtins.replaceStrings [ "{version}" ] [ p.version ] t.upstream.cpe
        else
          null;
      # the source's purl as written: commit links of backported patches
      pedigree = patches.of p (if known then t.upstream.purl else null);
    in
    withFields p (
      {
        type = if builtins.elem p roots then "application" else "library";
        bom-ref = ref p;
        name = p.pname or p.name;
      }
      // (if p ? version && p.version != "" then { inherit (p) version; } else { })
      // (if known then { inherit purl; } else { })
      // (if cpe == null then { } else { inherit cpe; })
      // (if hashes == [ ] then { } else { inherit hashes; })
      // (
        let
          when = c: value: if c then [ (approximation value) ] else [ ];
          properties =
            when (!known) "no sources.toml purl: name from the derivation, no purl"
            ++ when (hashes != [ ]) "sha256 of the unpacked source tree (NAR hash), not of the upstream archive"
            ++ when (known && match ".*[?].*" t.upstream.purl != null) "the sources.toml purl query is dropped"
            ++ when (isLibc p) "implicit dependency: every ELF links it, its dependsOn edges are inferred"
            ++ extraProperties p;
        in
        if properties == [ ] then { } else { inherit properties; }
      )
      // (if pedigree == [ ] then { } else { pedigree.patches = pedigree; })
    );

  graph = map (p: {
    ref = ref p;
    dependsOn = map ref (
      (if libc != null && !isLibc p then [ libc ] else [ ]) ++ filter (d: !isLibc d) (depsOf p)
    );
  }) pkgsOf;

  bom = {
    bomFormat = "CycloneDX";
    specVersion = "1.5";
    version = 1;
    metadata.component = {
      type = "application";
      inherit name;
      bom-ref = name;
    };
    metadata.properties = [
      (approximation "runtime graph from declared dependencies, not store references; buildDependencies left out")
    ];
    components = sort (a: b: a.bom-ref < b.bom-ref) (map component pkgsOf);
    dependencies = [
      {
        ref = name;
        dependsOn = map ref roots;
      }
    ]
    ++ sort (a: b: a.ref < b.ref) graph;
  };
in
derivation {
  name = "${name}-sbom";
  inherit system;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  json = builtins.toFile "sbom.json" (toJSON bom);
  builder = "${nu}/bin/nu";
  args = [
    "--no-config-file"
    "-c"
    "mkdir $env.out; cp $env.json ($env.out | path join sbom.json)"
  ];
}
// {
  inherit bom;
}
