# Test that a build without the python build system imports its build tools' modules
use checks.nu *
assert "build tools and what they propagate are on PYTHONPATH" ((open --raw $"($env.pkg)/share/imports" | str trim) == "imported")
done
