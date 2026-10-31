# Test that autoreconf with pkg.m4 and libtool.m4 from build tools works

use checks.nu *

let result = (^$"($env.pkg)/bin/hello" | str trim)
assert "hello built by autoreconf runs and found zlib through pkg.m4" ($result | str starts-with "Hello, autotools! zlib version:")

done
