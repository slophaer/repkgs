# A rustc cache hit from another Cargo.lock: the same crate, vendored under another store path.
# The dependency compiles once with vendor A (cargo.build). The `replay` phase points cargo at
# vendor B, which differs by one ignored file, so it has another store hash and the same masked name.
# jig replays the dependency from the cache, and the dep-info it writes must name vendor B: cargo
# reads the files a dep-info lists, and a missing one rebuilds the crate and reruns its build script
{ package }:
let
  vendor =
    dir:
    builtins.path {
      path = dir;
      name = "cargo-vendor";
    };
in
package {
  name = "test-cargo-vendor-replay";
  version = "1.0.0";
  source = ./src;
  uses = [ "cargo" ];
  cargo.deps = vendor ./vendor-a;
  env.VENDOR_B = vendor ./vendor-b;
  phases = [
    "cargo.build"
    {
      name = "replay";
      run = ''
        let a = (options cargo).deps
        let b = $env.VENDOR_B
        # a masked store path maps back to a file through the build's roots only. cargo's setup
        # added this build's vendor tree (A); a build against B has B instead (both mask to
        # "*-cargo-vendor", and jig keeps the first root of a name)
        let roots_with_a = ($env.JIG_STORE_ROOTS | split row " ")
        $env.JIG_STORE_ROOTS = ($roots_with_a | each {|r| if $r == $a { $b } else { $r } } | str join " ")
        let cfg = $"($env.CARGO_HOME)/config.toml"
        open --raw $cfg | str replace --all $a $b | save -f $cfg
        $env.CARGO_TARGET_DIR = $"($c.build)/target-b"
        x cargo build --release --offline
        let deps = $"($env.CARGO_TARGET_DIR)/($env.CARGO_BUILD_TARGET)/release/deps"
        let depfiles = (glob $"($deps)/dep-*.d" | each {|f| {name: ($f | path basename), text: (open --raw $f)} })
        # jig's log: the outcome of each rustc run, subject = crate name + extra-filename
        let rustc = (if ($env.JIG_LOG | path exists) {
          open --raw $env.JIG_LOG | lines | split column "\t" tool outcome subject | where tool == rustc and subject =~ '^dep-'
        } else { [] })
        mkdir $"($c.out)/share"
        {cache: $c.cache, vendor_a: $a, vendor_b: $b, roots: $roots_with_a, rustc: $rustc, depfiles: $depfiles}
          | to json | save $"($c.out)/share/runs.json"
      '';
    }
  ];
  tests.version = false;
}
