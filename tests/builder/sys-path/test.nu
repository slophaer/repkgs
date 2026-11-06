# The launcher's PATH: an ordinary dependency's bin/, not a system library's (sys)
use checks.nu *
let record = (open $"($env.pkg)/bin/.main.launch" | from json)
let path = ($record.env?.PATH?.prepend? | default [])
assert $"the ordinary dependency is on PATH: ($path)" ($path | any { $in =~ 'test-sys-path-tool/bin$' })
assert $"the system library is not: ($path)" (not ($path | any { $in =~ 'test-sys-path-lib/bin$' }))
done
