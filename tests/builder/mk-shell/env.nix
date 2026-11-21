# The shell is never built: the check gets what nix-shell and nix develop read from it
set:
let
  shell = set.mkShellNoCC {
    packages = [ set.pkgs.jq ];
    env.GREETING = "hi";
  };
  bare = set.mkShellNoCC {
    packages = [ set.pkgs.jq ];
    baseTools = [ ];
  };
in
{
  shellStdenv = shell.stdenv;
  bareStdenv = bare.stdenv;
  shellAttrs = builtins.toJSON (builtins.attrNames shell.drvAttrs);
  jq = set.pkgs.jq;
  # the default baseTools: the set's base userland and bash, no compiler
  baseBins = builtins.concatStringsSep ":" (
    map (p: "${p}/bin") (
      with set.pkgs;
      [
        coreutils
        findutils
        diffutils
        grep
        sed
        gawk
        bash
      ]
    )
  );
}
