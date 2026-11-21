# mkShell puts its tools on PATH from $stdenv/setup, which nix-shell (and direnv's `use nix`) and
# nix develop both source. A PATH attribute would replace the caller's PATH under nix-shell, and
# under --pure leave no tools at all
use checks.nu *

let attrs = ($env.shellAttrs | from json)
assert $"no PATH attribute: ($attrs)" (not ("PATH" in $attrs))
assert "env is an attribute" ("GREETING" in $attrs)
let setup = $"($env.shellStdenv)/setup"
assert $"the shell has a stdenv/setup: ($setup)" ($setup | path exists)

let sh = (which -a sh | where type == external | get path.0)
# PATH, PKG_CONFIG_PATH, CMAKE_PREFIX_PATH after sourcing setup in an environment of only vars
def sourced [...vars: string, --setup: string]: nothing -> list<string> {
  let setup = ($setup | default $"($env.shellStdenv)/setup")
  ^env -i ...$vars $sh -c $". ($setup) && printf '%s\n' \"$PATH\" \"$PKG_CONFIG_PATH\" \"$CMAKE_PREFIX_PATH\"" | lines
}

# PATH: the shell's packages, the set's base tools (so nix-shell --pure and nix develop -i
# have ls, rm and sh), then what PATH held: the caller's under nix-shell, direnv
let s = (sourced PATH=/caller/bin PKG_CONFIG_PATH=/caller/pc CMAKE_PREFIX_PATH=/caller)
assert $"nix-shell PATH: ($s)" ($s.0 == $"($env.jq)/bin:($env.baseBins):/caller/bin")
assert $"nix-shell PKG_CONFIG_PATH: ($s)" ($s.1 == $"($env.jq)/lib/pkgconfig:/caller/pc")
assert $"nix-shell CMAKE_PREFIX_PATH: ($s)" ($s.2 == $"($env.jq):/caller")
# nix develop sources it in the build sandbox, whose PATH is a placeholder; -i keeps the result
let d = (sourced PATH=/path-not-set)
assert $"nix develop PATH: ($d)" ($d.0 == $"($env.jq)/bin:($env.baseBins)")
# nix-shell --pure: PATH empty
let p = (sourced PATH= IN_NIX_SHELL=pure)
assert $"--pure PATH: ($p)" ($p.0 == $"($env.jq)/bin:($env.baseBins)")
let b = (sourced PATH= --setup $"($env.bareStdenv)/setup")
assert $"PATH with baseTools = []: ($b)" ($b.0 == $"($env.jq)/bin")
# nix-shell runs shellHook only through a runHook its setup defines (nix develop evaluates it)
let h = (^env -i PATH= "shellHook=echo hooked" $sh -c $". ($setup) && runHook shellHook" | complete)
assert $"runHook runs shellHook: ($h)" ($h.exit_code == 0 and ($h.stdout | str trim) == "hooked")
done
