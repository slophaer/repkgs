# Test that a build-machine program finds and runs against a build library
use checks.nu *
let ran = (open --raw $"($env.pkg)/share/zlib-version" | str trim)
let pc = (open --raw $"($env.pkg)/share/pc-version" | str trim)
assert "the generator linked zlib and ran" ($ran =~ '^\d+\.\d+')
assert "pkg-config for the build machine finds the build library" ($pc == $ran)
assert "a build library is no runtime dependency" (not (open --raw $"($env.pkg)/exports.json" | str contains zlib))
done
