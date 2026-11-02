# pkg.bin is what a package declares, at evaluation; exports.json `bin` is what bin/ holds after
# the build. A declared name must be installed. A library declares none. A wrapper keeps both.
use checks.nu *
let jq_bin = ($env.jqBin | from json)
assert $"jq declares jq by default: ($jq_bin)" ($jq_bin == ["jq"])
assert $"zlib declares no executables: ($env.zlibBin)" (($env.zlibBin | from json) == [])
let inv = (open $"($env.jq)/exports.json" | get bin)
assert $"jq's inventory holds its declaration: ($inv)" ($jq_bin | all { $in in $inv })
for b in $jq_bin { assert $"bin/($b) installed" ($"($env.jq)/bin/($b)" | path exists) }
assert $"wrapper keeps the declaration: ($env.wrappedBin)" (($env.wrappedBin | from json) == $jq_bin)
let winv = (open $"($env.wrapped)/exports.json" | get -o bin)
assert $"wrapper's inventory is what it wrapped: ($winv)" ($winv == $inv)
done
