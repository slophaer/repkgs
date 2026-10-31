# Test that autoreconf with pkg.m4 and libtool.m4 from build tools works
let result = (^$"($env.pkg)/bin/hello" | str trim)
if not ($result | str starts-with "Hello, autotools! zlib version:") {
  error make {msg: $"Expected output to start with 'Hello, autotools! zlib version:', got '($result)'"}
}
