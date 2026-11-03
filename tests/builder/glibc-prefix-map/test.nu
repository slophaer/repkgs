# The bootstrap glibc maps each build-input directory to its own placeholder, so the debug
# info names no store path and a debugger can map each placeholder back on its own.
use checks.nu *

mkdir recipe/bootstrap recipe/builder recipe/pkgs/x/x
cp $env.glibcRecipe recipe/pkgs/x/x/glibc.nu
cp $env.bootstrapLib recipe/bootstrap/lib.nu
cp $env.bootstrapGlob recipe/builder/glob.nu
cp $env.bootstrapLog recipe/builder/log.nu
let maps = (^nu --no-config-file -c 'use recipe/pkgs/x/x/glibc.nu prefix-maps; prefix-maps /nix/store/aaa-compiler-rt /nix/store/bbb-linux-headers | to json' | from json)
assert "one map per build input" ($maps == [
  "-ffile-prefix-map=/nix/store/aaa-compiler-rt=/build-input/compiler-rt"
  "-ffile-prefix-map=/nix/store/bbb-linux-headers=/build-input/linux-headers"
])
done
