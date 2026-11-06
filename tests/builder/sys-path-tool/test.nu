use checks.nu *
assert "the dependency ships a program" ($"($env.pkg)/bin/tool" | path exists)
done
