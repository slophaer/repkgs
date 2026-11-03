# A CycloneDX 1.5 SBOM for the runtime closure of some packages, from evaluation alone (no IFD).
#   sbom { roots = [ pkgs.jq ]; name = "jq"; }   a derivation whose output has sbom.json
# The closure is the `dependencies` graph of the packages (the attribute nix/package.nix hands to
# the derivation: package.nix's own list plus [pin] sys libraries and the build systems'), not the
# store references. Version, purl and source hash come from each package's directory:
# `dir`/sources.toml `[upstream] purl`, the pinned version (`version`) and the source fetch's
# `outputHash` (`src`). `libc0` ({ name, dir } or null) is implicit in every ELF link and a bootstrap
# stage with no package of its own, so it joins as a component read from its directory's
# sources.toml, and in the dependsOn of each other one.
#
# Approximations, all marked with a `golconda:approximation` property on the component:
#  - a derivation without `dir` (toolchain, bootstrap stages, seed) has no sources.toml: name and
#    derivation name only, no purl, no version, no hash
#  - hashes are SHA-256 of the unpacked source tree (the NAR hash of what the fetch yields), not
#    of the upstream tarball
#  - a purl's query (uptrack's `?url=…&regex=…` of pkg:generic) is dropped
#  - build-only tools (`buildDependencies`) are left out on purpose: they are not in the runtime
#    closure
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
}:
let
  inherit (builtins)
    convertHash
    elemAt
    filter
    fromTOML
    genericClosure
    head
    match
    pathExists
    readFile
    sort
    split
    toJSON
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

  key = p: p.name;
  # `dependencies` of a package; anything that is not a package has none
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

  tomlOf =
    p:
    if p ? dir && pathExists (p.dir + "/sources.toml") then
      fromTOML (readFile (p.dir + "/sources.toml"))
    else
      null;

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
  ref = p: if p ? version then "${p.pname or p.name}@${p.version}" else key p;

  component =
    p:
    let
      t = tomlOf p;
      known = t != null && t ? upstream.purl && p ? version;
      hashes = if t == null then [ ] else hashesOf p;
      properties =
        (
          if known then
            [ ]
          else
            [
              {
                name = "golconda:approximation";
                value = "no sources.toml purl: name from the derivation, no purl";
              }
            ]
        )
        ++ extraProperties p;
    in
    {
      type = if builtins.elem p roots then "application" else "library";
      bom-ref = ref p;
      name = p.pname or p.name;
    }
    // (if p ? version && p.version != "" then { inherit (p) version; } else { })
    // (if known then { purl = purlOf p t; } else { })
    // (if hashes == [ ] then { } else { inherit hashes; })
    // (if properties == [ ] then { } else { inherit properties; });

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
