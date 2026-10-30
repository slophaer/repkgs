# wrap: create launch records that chain to a wrapped package's binaries.
# For each bin/<x> of the package, writes bin/.<x>.launch with:
#   { program: "{store}/<hash>-pkg/bin/<x>", args: argv, env: env }
# Links the rest of the package's trees so the wrapper stands in for the original.

use core.nu *

# store paths -> {root}/{store} templates launch expands
def storerel [p: string, out: string]: nothing -> string {
  $p | str replace -a $out "{root}" | str replace -a $env.NIX_STORE "{store}"
}

# link at `from` pointing to `to`, both absolute: the relative target
def relative-link [from: string, to: string]: nothing -> string {
  let f = ($from | path split | drop 1 | skip 1)
  let t = ($to | path split | skip 1)
  let common = ($f | zip $t | take while { $in.0 == $in.1 } | length)
  $f | skip $common | each { ".." } | append ($t | skip $common) | path join
}

# Link directory contents from the package to the wrapper output.
# Does not link bin/ (we create our own launchers there).
def link-tree [pkg: string, out: string]: nothing -> nothing {
  mkdir $out
  let entries = (ls $pkg | where name !~ '/bin$' | where name !~ '/exports\.json$')
  for e in $entries {
    let rel = ($e.name | path relative-to $pkg)
    let target = $"($out)/($rel)"
    let link = (relative-link $target $e.name)
    ^ln -sf $link $target
  }
}

# Read the platform record from structured attrs
def get-platform []: nothing -> record {
  open $env.NIX_ATTRS_JSON_FILE | get platform
}

# Main entry point: create launchers for all binaries in the package
export def main [pkg: string, argv: list<string>, env_spec: record]: nothing -> nothing {
  let platform = (get-platform)
  let out = $env.out
  let bindir = $"($pkg)/bin"

  # Link non-bin trees from the wrapped package
  link-tree $pkg $out

  # If no bin/ in the package, we're done
  if not ($bindir | path exists) {
    return
  }

  mkdir $"($out)/bin"

  # Find all executables in bin/ (skip hidden files which are already launchers)
  let entries = (ls $bindir | get name | where { ($in | path basename) !~ '^\.' })

  for f in $entries {
    let name = ($f | path basename)
    let exe = $platform.ext?.exe? | default ""

    # The program path in the chained record points to the wrapped package's binary
    # If the original is already a launcher (symlink to launch), chain to its .name instead
    let target = (if ($f | path type) == "symlink" and (^readlink $f | path basename) == "launch" {
      # It's a launcher - chain to the real program
      $"($bindir)/.($name)"
    } else {
      $f
    })

    # Convert env to the record format: { VAR: { op: value } }
    # Also apply storerel to values
    let env_record = ($env_spec | items {|k, v|
      let ops = ($v | items {|op, val|
        let expanded = (if ($val | describe) =~ "list" {
          $val | each { storerel $in $out }
        } else {
          storerel $val $out
        })
        [$op $expanded]
      } | into record)
      [$k $ops]
    } | into record)

    # Build the launch record
    # Never set argv0 in a chained record - it would loop
    let record = {
      program: (storerel $target $out)
      args: ($argv | each { storerel $in $out })
      env: $env_record
    } | (if ($in.args | is-empty) { reject args } else { $in })
      | (if ($in.env | is-empty) { reject env } else { $in })

    # Write the launch record
    $record | to json -r | save -f $"($out)/bin/.($name)($exe).launch"

    # Create the launcher symlink/copy (relative, for relocatability)
    if $platform.binfmt == "coff" {
      cp $platform.launch $"($out)/bin/($name)($exe)"
    } else {
      let link = (relative-link $"($out)/bin/($name)" $platform.launch)
      ^ln -sf $link $"($out)/bin/($name)"
    }

    print -e $"wrap: bin/($name) -> ($target)"
  }

  # Write exports.json so this package can be a dependency
  {
    name: ($pkg | path basename | str substring 33.. | str replace -r '-(x86_64|aarch64|riscv64|loongarch64|powerpc64le)-[\w-]+$' '' | $"($in)-wrap")
    exports: false
  } | to json | save -f $"($out)/exports.json"
}
