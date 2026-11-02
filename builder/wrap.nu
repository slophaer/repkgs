# wrap: create launch records that chain to a wrapped package's binaries.
# For each bin/<x> of the package, writes bin/.<x>.launch with:
#   { program: "{store}/<hash>-pkg/bin/<x>", args: argv, env: env }
# program is the package's own bin/<x>, launcher or not, so its record (args, env, interpreter)
# still applies after ours. Links the rest of the package's trees so the wrapper stands in for
# the original; files land in share/wrap/<pname>/.

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

# files {name: text} into share/wrap/<pname>/. A linked share/ becomes a real directory of links
def write-files [out: string, pname: string, files: record]: nothing -> nothing {
  if ($files | is-empty) { return }
  let share = $"($out)/share"
  if ($share | path type) == "symlink" {
    let target = ($share | path dirname | path join (^readlink $share) | path expand)
    rm $share
    mkdir $share
    for e in (ls $target) { ^ln -sr $e.name $"($share)/($e.name | path basename)" }
  }
  let dir = $"($share)/wrap/($pname)"
  mkdir $dir
  for f in ($files | transpose name text) {
    if $f.name in ["" "." ".."] or ($f.name | str contains "/") {
      error make {msg: $"wrap: file name '($f.name)' must be a plain name"}
    }
    $f.text | save -f $"($dir)/($f.name)"
  }
}

# Create launchers for all binaries in the package, then the files
export def main [pkg: string, argv: list<string>, env_spec: record, files: record, pname: string]: nothing -> nothing {
  let platform = (open $env.NIX_ATTRS_JSON_FILE | get platform)
  let out = $env.out
  let bindir = $"($pkg)/bin"
  let exe = ($platform.ext?.exe? | default "")

  link-tree $pkg $out

  # skip hidden files: they are the package's own launch records and real binaries
  let entries = (if ($bindir | path exists) { ls $bindir | get name | where { ($in | path basename) !~ '^\.' } } else { [] })
  # bin/<x>.exe on PE: the record is .<x>.exe.launch
  let names = ($entries | each { path basename | str replace -r $"($exe | str replace -a '.' '\.')$" "" })
  if ($entries | is-not-empty) { mkdir $"($out)/bin" }

  # { VAR: { op: value } } with store paths as templates
  let env_record = ($env_spec | items {|k, v|
    [$k ($v | items {|op, val| [$op (if ($val | describe) =~ "list" { $val | each { storerel $in $out } } else { storerel $val $out })] } | into record)]
  } | into record)

  for e in ($entries | zip $names) {
    let f = $e.0
    let name = $e.1
    # Never set argv0 in a chained record - it would loop
    let record = {
      program: (storerel $f $out)
      args: ($argv | each { storerel $in $out })
      env: $env_record
    } | (if ($in.args | is-empty) { reject args } else { $in })
      | (if ($in.env | is-empty) { reject env } else { $in })
    $record | to json -r | save -f $"($out)/bin/.($name)($exe).launch"

    # the launcher: a relative symlink, a copy on PE
    if $platform.binfmt == "coff" {
      cp $platform.launch $"($out)/bin/($name)($exe)"
    } else {
      ^ln -sf (relative-link $"($out)/bin/($name)" $platform.launch) $"($out)/bin/($name)"
    }
    print -e $"wrap: bin/($name) -> ($f)"
  }

  write-files $out $pname $files

  # exports.json so this package can be a dependency; bin is what bin/ holds, as finish writes it
  {
    name: ($pkg | path basename | str substring 33.. | str replace -r '-(x86_64|aarch64|riscv64|loongarch64|powerpc64le)-[\w-]+$' '' | $"($in)-wrap")
    exports: false
    bin: $names
  } | to json | save -f $"($out)/exports.json"
}
