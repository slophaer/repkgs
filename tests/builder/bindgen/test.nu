# Test that bindgen found <stdio.h> in the toolchain's sysroot and <zlib.h> in a dependency
use checks.nu *
let rs = (open --raw $"($env.pkg)/share/bindings.rs")
assert "libc header parsed" ($rs | str contains "pub fn snprintf")
assert "dependency header parsed" ($rs | str contains "pub fn zlibVersion")
done
