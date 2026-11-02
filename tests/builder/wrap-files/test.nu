# wrap with files, argv and env: the files land in share/wrap/<pkg>/, the launcher passes the argv
# prefix before the caller's arguments, and the share tree stays linked by relative links.
# Apostrophes in names and values pass through unchanged.
use checks.nu *
let w = $env.wrapped
let f = $"($w)/share/wrap/test-wrap-files/a.conf"
assert "file written under share/wrap/<pkg>/" ($f | path exists)
assert $"file content: (open --raw $f | to json)" ((open --raw $f) == "hello")
let q = $"($w)/share/wrap/test-wrap-files/it's.conf"
assert "a file name with an apostrophe" ($q | path exists)
assert $"apostrophes in file content: (open --raw $q | to json)" ((open --raw $q) == "say 'hi'\n")
assert "share/ is a real directory now" (($"($w)/share" | path type) == "dir")
assert "the package's share/data is still reachable" ((open --raw $"($w)/share/data/README") == "docs\n")

let out = (^$"($w)/bin/args" caller | lines)
let want = ["--inner" "--conf" $f "it's" "caller" "INNER=inner" "OUTER=o'k"]
assert $"argv and env with apostrophes: ($out | to json -r)" ($out == $want)

# regression for 16928d4: no absolute link anywhere in the output
let abs = (^find $w -lname '/*' | lines)
assert $"no absolute symlink in the output: ($abs)" ($abs | is-empty)
done
