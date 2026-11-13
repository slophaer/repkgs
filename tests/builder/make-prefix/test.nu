# Test that make configures and installs for the declared prefix, and staged roots land where the
# package declared them
use checks.nu *
let p = $env.pkg
assert "installed below the prefix" ($"($p)/bin/hello" | path exists)
assert "configure got the declared prefix" ((open --raw $"($p)/share/hello/configured-prefix" | str trim) == "/usr")
assert "/etc moved to share/factory/etc" ($"($p)/share/factory/etc/hello/hello.conf" | path exists)
assert "/var dropped" (not ($"($p)/var" | path exists) and (^find $p -name state | str trim) == "")
assert "no etc/ at the top" (not ($"($p)/etc" | path exists))
done
