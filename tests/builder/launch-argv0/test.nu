# The launcher finds its record from the file the kernel ran (AT_EXECFN) when argv[0] is a bare
# name: a program that execs a helper by its full path but names it by its basename (gnupg starts
# gpg-agent so) must not depend on PATH. argv[0] reaches the program unchanged
use checks.nu *

let hello = $"($env.pkg)/bin/hello"
let exec_as = $"($env.pkg)/libexec/exec-as"
assert "bin/hello is a launcher" (($hello | path type) == symlink and ($"($env.pkg)/bin/.hello.launch" | path exists))

def run-as [file: string, argv0: string, --path: string = ""]: nothing -> string {
  let r = (with-env {PATH: $path} { ^$exec_as $file $argv0 | complete })
  assert $"($file) as ($argv0) runs: ($r.stdout)($r.stderr)" ($r.exit_code == 0)
  $r.stdout | str trim
}

# not on PATH, by its full path and from a relative one
assert "full path, bare argv[0]" ((run-as $hello hello) == "hello hello")
cd $env.pkg
assert "relative path, bare argv[0]" ((run-as bin/hello hello) == "hello hello")
cd /
# PATH names another program of that name first: the file that ran still wins
let decoy = $"($env.TMPDIR? | default /tmp)/decoy"
mkdir $decoy
"#!/bin/sh\necho decoy\n" | save -f $"($decoy)/hello"
^chmod +x $"($decoy)/hello"
assert "a decoy on PATH is not taken" ((run-as $hello hello --path $decoy) == "hello hello")
# the usual case: found on PATH by name
let r = (with-env {PATH: $"($env.pkg)/bin:($env.PATH)"} { ^hello | complete })
assert $"found on PATH: ($r.stdout)($r.stderr)" ($r.exit_code == 0 and ($r.stdout | str starts-with "hello "))
# a path in argv[0] is still what selects the record
assert "argv[0] with a slash" ((run-as $hello $hello) == $"hello ($hello)")
print "launch-argv0: bare argv[0] found through AT_EXECFN, PATH lookup and path argv[0] kept"
done
