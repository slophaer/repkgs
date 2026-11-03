# exports.json `bin`: the executables bin/ holds after the build, for consumers that link names.
use checks.nu *
use exports.nu [list-bin]
let jq = (open $"($env.jq)/exports.json" | get bin)
assert $"jq's inventory: ($jq)" ($jq == ["jq"])
let zlib = (open $"($env.zlib)/exports.json" | get bin)
assert $"zlib installs no executables: ($zlib)" ($zlib == [])
# the platform's executable suffix is literal text, and hidden entries are not listed
let root = $"($env.TMPDIR? | default /tmp)/bin-inventory"
rm -rf $root
mkdir $"($root)/bin"
for name in [annexe tool.exe .hidden.exe] {
  "fixture" | save $"($root)/bin/($name)"
  chmod +x $"($root)/bin/($name)"
}
assert "strip the literal exe suffix only" ((list-bin $root {ext: {exe: '.exe'}} | sort) == [annexe tool])
assert "no suffix on unix" ((list-bin $root {ext: {exe: ''}} | sort) == [annexe tool.exe])
rm -rf $root
done
