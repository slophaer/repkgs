use checks.nu *
let syms = {|f| ^llvm-nm $"($env.pkg)/lib/($f).o" | lines | each { split row " " | last } }
# only JIG_PASSTHROUGH=1 turns the policy off; every other value keeps the normal build
for f in [unset empty zero false off true yes] {
  assert $"($f): normal build is hardened (fortify)" ("fortified" in (do $syms $f))
  assert $"($f): normal build is hardened (stack protector)" ("__stack_chk_fail" in (do $syms $f))
}
assert "passthrough: no fortify define" ("fortified" not-in (do $syms one))
assert "passthrough: no stack protector" ("__stack_chk_fail" not-in (do $syms one))
let cxx = (^llvm-nm $"($env.pkg)/lib/one-cxx.o" | str join "\n")
assert "passthrough c++: no fortify define" (not ($cxx =~ "fortified"))
assert "passthrough c++: no stack protector" (not ($cxx =~ "__stack_chk_fail"))
done
