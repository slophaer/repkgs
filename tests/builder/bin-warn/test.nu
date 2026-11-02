# finish's bin warning: regular executable files directly in bin/ that spec.bin does not declare.
# Directories, nested files and entries prune removes are not warned about.
use finish.nu [inventory prune undeclared-bin]
use checks.nu *

let root = $"($env.TMPDIR? | default /tmp)/bin-warn-check"
rm -rf $root
mkdir $"($root)/bin/sub" $"($root)/lib"
"#!/bin/sh\n" | save -f $"($root)/bin/real"
chmod +x $"($root)/bin/real"
"data" | save -f $"($root)/bin/data"
"junk" | save -f $"($root)/bin/old.la"
chmod +x $"($root)/bin/old.la"
"inner" | save -f $"($root)/bin/sub/inner"
chmod +x $"($root)/bin/sub/inner"

let inv = (prune $root (inventory $root))
let platform = {ext: {exe: ""}}
assert "only bin/real is undeclared, not dirs, nested files or pruned .la" ((undeclared-bin $inv [] $platform) == [real])
assert "a declared executable makes no warning" ((undeclared-bin $inv [real] $platform) | is-empty)
rm -rf $root
done
