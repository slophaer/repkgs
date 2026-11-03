# nix/platforms.nix: every linux cpu's systemd-repart architecture and EFI name, asserted at
# evaluation. `mk` falls back to the cpu name for a missing mapping, so a typo or an omission
# would otherwise go unnoticed. uefi = null says the cpu has no UEFI port.
{
  system ? builtins.currentSystem,
  nixpkgs ? import ../nix/nixpkgs.nix,
}:
let
  pkgs = import nixpkgs { inherit system; };
  platforms = import ../nix/platforms.nix;
  expected = {
    x86_64 = {
      systemd = "x86-64";
      uefi = "x64";
    };
    aarch64 = {
      systemd = "arm64";
      uefi = "aa64";
    };
    riscv64 = {
      systemd = "riscv64";
      uefi = "riscv64";
    };
    loongarch64 = {
      systemd = "loongarch64";
      uefi = "loongarch64";
    };
    powerpc64le = {
      systemd = "ppc64-le";
      uefi = null; # no UEFI port
    };
  };
  actual = builtins.mapAttrs (cpu: _: {
    inherit (platforms.byName."${cpu}-linux".names) systemd uefi;
  }) expected;
  # a new cpu with a -linux platform must state both names here too
  linuxCpus = builtins.map (n: builtins.replaceStrings [ "-linux" ] [ "" ] n) (
    builtins.filter (n: builtins.match ".*-linux" n != null) (builtins.attrNames platforms.byName)
  );
in
assert actual == expected;
assert builtins.sort builtins.lessThan linuxCpus == builtins.attrNames expected;
pkgs.runCommand "check-platforms" { } "touch $out"
