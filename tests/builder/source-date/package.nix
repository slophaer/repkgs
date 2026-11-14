# SOURCE_DATE_EPOCH follows the [pin] date of sources.toml (midnight UTC): records what the build
# saw and what clang made of it
{ package }:
package {
  name = "test-source-date";
  source = ./src;
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/share"
        x cc stamp.c -o stamp
        ^./stamp | save $"($c.out)/share/stamp"
        $env.SOURCE_DATE_EPOCH | save $"($c.out)/share/source-date-epoch"
        $env.KBUILD_BUILD_TIMESTAMP | save $"($c.out)/share/kbuild-build-timestamp"
      '';
    }
  ];
}
