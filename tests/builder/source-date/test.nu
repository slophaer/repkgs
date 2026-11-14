# SOURCE_DATE_EPOCH is the package's [pin] date at midnight UTC, never before 1980-01-01 (the
# earliest ZIP mtime), and 1980-01-01 for a package with no date
use checks.nu *
use env.nu [source-date-epoch]

let share = $"($env.pkg)/share"
let sde = (open --raw $"($share)/source-date-epoch" | str trim)
assert $"SOURCE_DATE_EPOCH is the pin date 2026-09-16: ($sde)" ($sde == "1789516800")
let kbuild = (open --raw $"($share)/kbuild-build-timestamp" | str trim)
assert $"KBUILD_BUILD_TIMESTAMP follows it: ($kbuild)" ($kbuild == "@1789516800")
let stamp = (open --raw $"($share)/stamp" | str trim)
assert $"clang's __DATE__ __TIME__ follow it: ($stamp)" ($stamp == "Sep 16 2026 00:00:00")

assert "no date: 1980-01-01" ((source-date-epoch) == 315532800)
assert "a date before 1980: 1980-01-01" ((source-date-epoch "1975-06-01") == 315532800)
assert "a date: its midnight UTC" ((source-date-epoch "2026-09-16") == 1789516800)
fails "a date that does not exist" { source-date-epoch "2026-02-30" }
done
