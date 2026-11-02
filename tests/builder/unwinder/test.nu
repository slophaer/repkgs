use checks.nu *

mkdir recipe/bootstrap recipe/builder recipe/pkgs/x/x runtime/lib bundle/lib
cp $env.glibcRecipe recipe/pkgs/x/x/glibc.nu
cp $env.bootstrapLib recipe/bootstrap/lib.nu
cp $env.bootstrapGlob recipe/builder/glob.nu
cp $env.bootstrapLog recipe/builder/log.nu
let run = {
  with-env {runtime: ($env.PWD | path join runtime), bundle: ($env.PWD | path join bundle)} {
    ^nu --no-config-file -c 'use recipe/pkgs/x/x/glibc.nu install-unwinder; install-unwinder $env.runtime $env.bundle' | complete
  }
}
let missing = (do $run)
assert "missing unwinder fails" ($missing.exit_code != 0)
assert "missing unwinder is named" ($missing.stderr | str contains "libunwind.so.1.0")
"unwinder\n" | save runtime/lib/libunwind.so.1.0
let present = (do $run)
assert "present unwinder copies" ($present.exit_code == 0)
assert "unwinder content" ((open --raw bundle/lib/libunwind.so.1.0) == "unwinder\n")
assert "soname is a relative link" ((^readlink bundle/lib/libunwind.so.1 | str trim) == "libunwind.so.1.0")
done
