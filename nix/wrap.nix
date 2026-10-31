# wrap { package; argv ? []; env ? {}; files ? {}; }: a package that wraps another.
# For each bin/<x> of the wrapped package, writes bin/.<x>.launch as a chained record:
#   { program: "{store}/<hash>-pkg/bin/<x>", args: argv, env: env }
# Links the rest of the package's trees (share/, lib/, etc.) so the wrapper stands in.
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
    attrNames
    toJSON
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
  # write each file to share/wrap/<name>/ at build time, AFTER link-tree ran
  # (link-tree may have created share/ as a symlink; we convert it to a real
  # directory with symlinked contents so wrap/<name>/ can be a real directory)
  filesScript =
    if files == { } then
      ""
    else
      ''
        # if share is a symlink from link-tree, expand it to a real directory
        let share_dir = $"($env.out)/share"
        if ($share_dir | path type) == "symlink" {
          # readlink gives relative path; resolve it from share_dir's parent
          let rel_target = (^readlink $share_dir)
          let target = ($share_dir | path dirname | path join $rel_target | path expand)
          rm $share_dir
          mkdir $share_dir
          for e in (ls $target) {
            let name = ($e.name | path basename)
            ^ln -sr $e.name $"($share_dir)/($name)"
          }
        } else if not ($share_dir | path exists) {
          mkdir $share_dir
        }
        mkdir $"($share_dir)/wrap/${package.pname}"
        ${
          concatStringsSep "\n" (
            map (n: ''${toJSON files.${n}} | save -f $"($share_dir)/wrap/${package.pname}/${n}"'') (
              attrNames files
            )
          )
        }
      '';

  script = ''
    use core.nu *
    use wrap.nu

    # parse structured attrs
    let attrs = (open $env.NIX_ATTRS_JSON_FILE)
    $env.out = $attrs.outputs.out
    $env.NIX_STORE = ($env.out | path dirname)
    # Set PATH from the derivation attribute
    $env.PATH = $attrs.PATH

    # call the wrap builder first (creates share/ as a symlink if the package has one)
    let argv = ('${toJSON argv}' | from json)
    let env_spec = ('${toJSON env}' | from json)
    wrap $attrs.package $argv $env_spec

    # now create files in share/wrap/<name>/, expanding the share symlink if needed
    ${filesScript}
  '';

  drv = derivation {
    name = "${package.pname}-wrap";
    inherit (platform) system;
    __structuredAttrs = true;
    __contentAddressed = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    builder = "${nu}/bin/nu";
    args = nuArgs ++ [ script ];
    outputs = [ "out" ];
    inherit package;
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
  platform = platform.name;
  supported = package.supported or true;
  unsupportedReason = package.unsupportedReason or null;
}
