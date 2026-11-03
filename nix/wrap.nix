# wrap { package; argv ? []; env ? {}; files ? {}; }: a package that wraps another.
# For each bin/<x> of the wrapped package, writes bin/.<x>.launch as a chained record:
#   { program: "{store}/<hash>-pkg/bin/<x>", args: argv, env: env }
# The package's own launcher runs next, so its args, env and interpreter still apply.
# Links the rest of the package's trees (share/, lib/, etc.) so the wrapper stands in.
# The output is named <pname>-<version>-wrap and carries pname, version, bin and wraps.
# files are written under share/wrap/<name>/ so argv can reference them as {root}/share/wrap/<name>/<file>.
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
  package,
  argv ? [ ],
  env ? { },
  files ? { },
}:
let
  # argv, env and files reach the builder as structured attrs, never as source text
  script = ''
    use core.nu *
    use wrap.nu

    let attrs = (open $env.NIX_ATTRS_JSON_FILE)
    $env.out = $attrs.outputs.out
    $env.NIX_STORE = ($env.out | path dirname)
    $env.PATH = $attrs.PATH
    wrap $attrs.package $attrs.argv $attrs.launchEnv $attrs.files $attrs.pname
  '';

  drv = derivation {
    name = "${package.pname}-${package.version}-wrap";
    inherit (platform) system;
    __structuredAttrs = true;
    __contentAddressed = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    builder = "${nu}/bin/nu";
    args = nuArgs ++ [ script ];
    outputs = [ "out" ];
    inherit package argv files;
    inherit (package) pname;
    # launch's env operations, { VAR = { set = "…"; }; }
    launchEnv = env;
    platform = {
      inherit (platform)
        name
        binfmt
        ;
      ext = platform.ext or { };
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
  inherit (package) pname version;
  # the executables the package declares: the wrapper launches the same names
  bin = package.bin or [ ];
  # the package this one stands in for, so consumers can map the wrapper back to it
  wraps = package;
  platform = platform.name;
  supported = package.supported or true;
  unsupportedReason = package.unsupportedReason or null;
}
