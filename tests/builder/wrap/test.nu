use checks.nu *
assert "wrapped name carries the version" ($env.wrappedName == $env.wrappedWant)
assert "store path ends with the name" ($env.wrapped | str ends-with $"-($env.wrappedWant)")
assert "launcher written" ($"($env.wrapped)/bin/.tz.launch" | path exists)
done
