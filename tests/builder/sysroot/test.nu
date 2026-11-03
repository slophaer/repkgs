use checks.nu *

# Use the real recipe with the seed's cp, including its same-inode behavior.
mkdir recipe/bootstrap recipe/builder
cp $env.sysrootRecipe recipe/bootstrap/sysroot.nu
cp $env.bootstrapLib recipe/bootstrap/lib.nu
cp $env.bootstrapGlob recipe/builder/glob.nu
cp $env.bootstrapLog recipe/builder/log.nu
let recipe = ($env.PWD | path join recipe/bootstrap/sysroot.nu)

for linked in [false true] {
  let root = ($env.PWD | path join (if $linked { "linked" } else { "separate" }))
  mkdir $"($root)/a/lib" $"($root)/b/lib" $"($root)/resource"
  "unwinder\n" | save $"($root)/a/lib/libunwind.so.1.0"
  if $linked {
    ^ln $"($root)/a/lib/libunwind.so.1.0" $"($root)/b/lib/libunwind.so.1.0"
  } else {
    cp $"($root)/a/lib/libunwind.so.1.0" $"($root)/b/lib/libunwind.so.1.0"
  }
  let out = $"($root)/out"
  let result = (with-env {out: $out, parts: $"($root)/a ($root)/b", resource: $"($root)/resource"} {
    ^nu --no-config-file $recipe | complete
  })
  assert $"sysroot builds, linked=($linked)" ($result.exit_code == 0)
  let link = $"($out)/lib/libunwind.so.1.0"
  assert $"later part wins, linked=($linked)" (($link | path expand) == $"($root)/b/lib/libunwind.so.1.0")
  assert "link is relative" (not ((^readlink $link | str trim) | str starts-with "/"))
}
done
