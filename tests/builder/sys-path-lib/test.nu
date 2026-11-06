use checks.nu *
assert "the library ships a program" ($"($env.pkg)/bin/lib-tool" | path exists)
done
