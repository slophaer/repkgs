# closure { roots; name; }: a tarball of the closure of roots with a bin/ profile.
# The tarball holds:
#   <prefix>/nix/store/<hash>-* for every runtime path of the roots
#   bin/ with relative symlinks to the roots' launchers
# On any Linux host: tar x && PATH=$PWD/bin:$PATH runs the tools (needs /proc; glibc is inside).
{
  platform,
  launch,
  baseTools,
  nu,
}:
let
  inherit (builtins)
    concatStringsSep
    map
    ;
  tree = builtins.path {
    path = ../builder;
    name = "build";
  };
  nuArgs = [
    "--no-config-file"
    "--include-path=${tree}"
    "--experimental-options=[cell-path-types]"
    "-c"
  ];
in
{
  roots,
  name,
}:
let
  script = ''
    use core.nu *
    use closure.nu

    # parse structured attrs
    let attrs = (open $env.NIX_ATTRS_JSON_FILE)
    $env.out = $attrs.outputs.out
    $env.NIX_STORE = "/nix/store"
    $env.PATH = $attrs.PATH

    # call the closure builder
    closure $attrs.roots $attrs.name
  '';

  drv = derivation {
    inherit name;
    inherit (platform) system;
    __structuredAttrs = true;
    __contentAddressed = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    builder = "${nu}/bin/nu";
    args = nuArgs ++ [ script ];
    outputs = [ "out" ];
    inherit roots;
    # Nix computes the closure and passes it as a structured reference graph
    exportReferencesGraph.closure = roots;
    platform = {
      inherit (platform)
        name
        binfmt
        ;
      launch =
        if platform.binfmt == "elf" then
          "${launch}/bin/launch"
        else if platform.os == "windows" then
          "${launch}/bin/launch.exe"
        else
          "";
    };
    PATH = concatStringsSep ":" (map (t: "${t}/bin") baseTools.full);
  };
in
drv
// {
  pname = name;
  platform = platform.name;
}
