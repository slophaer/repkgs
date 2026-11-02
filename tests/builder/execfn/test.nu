# Without /proc (an initrd's init) crt-interp and ld.so find the executable's directory from
# AT_EXECFN. The kernel starts init as /init, a symlink into the store: the directory must be the
# target's, through links to links, relative and absolute, and from a relative name
use checks.nu *

let zv = $"($env.pkg)/bin/zv"
let t = $"($env.TMPDIR? | default /tmp)/execfn-test"
mkdir $"($t)/mid/bin" $"($t)/farm/bin"
^ln -s $zv $"($t)/mid/bin/zv"                 # absolute, into the store
^ln -s ../../mid/bin/zv $"($t)/farm/bin/zv"   # relative, to a link
^ln -s farm/bin/zv $"($t)/init"               # what the kernel execs: /init
^ln -s farm $"($t)/farmdir"                   # a linked directory on the way

let mnt = (which mount | get path.0)
# /proc hidden by an empty tmpfs in a private mount namespace, then `cmd` exec'd from `t`
def noproc [cmd: string]: nothing -> string {
  let r = (^unshare -rm sh -c $"($mnt) -t tmpfs none /proc && cd ($t) && test ! -e /proc/self/exe && exec ($cmd)" | complete)
  assert $"without /proc, ($cmd) runs: ($r.stdout)($r.stderr)" ($r.exit_code == 0)
  $r.stdout
}
let probe = (^unshare -rm sh -c $"($mnt) -t tmpfs none /proc && test ! -e /proc/self/exe" | complete)
if $probe.exit_code != 0 {
  print $"execfn: no user namespace here, cannot hide /proc: ($probe.stderr | str trim)"
  exit 1
}
for cmd in [$"($t)/init" $"($t)/farm/bin/zv" $"($t)/farmdir/bin/zv" "./init" "farm/bin/zv" $zv] {
  let stdout = (noproc $cmd)
  assert $"without /proc, ($cmd) loads libz: ($stdout)" ($stdout | str starts-with "zlib ")
}
print "execfn: /proc hidden, 6 ways of naming the program load interpreter and libz"
done
