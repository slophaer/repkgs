use checks.nu *
let syms = {|f| ^llvm-nm $"($env.pkg)/lib/($f).o" | lines | each { split row " " | last } }
assert "normal build is hardened (fortify)" ("fortified" in (do $syms normal))
assert "normal build is hardened (stack protector)" ("__stack_chk_fail" in (do $syms normal))
assert "passthrough: no fortify define" ("fortified" not-in (do $syms raw))
assert "passthrough: no stack protector" ("__stack_chk_fail" not-in (do $syms raw))
done
