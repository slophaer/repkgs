# a wrapper chains to the wrapped package's launcher, so that one's own record still applies:
# its args come first, its env stays, a script keeps its interpreter. The declaration carries over.
use checks.nu *
let w = $env.wrapped
let out = (^env -i $"($w)/bin/args" caller | lines)
let want = ["--inner" "--outer" "caller" "INNER=inner" "OUTER=outer"]
assert $"inner args and env kept: ($out | to json -r)" ($out == $want)
let g = (^env -i $"($w)/bin/greet" x | str trim)
assert $"script keeps its interpreter: ($g)" ($g == "greet --outer x")
assert $"wrapper declares the same bin: ($env.wrappedBin)" (($env.wrappedBin | from json) == ($env.innerBin | from json))
let rec = (open --raw $"($w)/bin/.args.launch" | from json)
assert $"record names the wrapped launcher: ($rec.program)" ($rec.program =~ '^\{store\}/[^/]+-test-wrap-files[^/]*/bin/args$')
done
