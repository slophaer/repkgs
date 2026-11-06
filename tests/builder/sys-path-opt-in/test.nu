# sysTools: the library's bin/ is on PATH again, beside the ordinary dependency's
use checks.nu *
let record = (open $"($env.pkg)/bin/.main.launch" | from json)
let path = ($record.env?.PATH?.prepend? | default [])
assert $"the ordinary dependency is on PATH: ($path)" ($path | any { $in =~ 'test-sys-path-tool/bin$' })
assert $"the opted-in library is too: ($path)" ($path | any { $in =~ 'test-sys-path-lib/bin$' })
done
