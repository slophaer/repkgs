{ package }:
package {
  name = "test-cc-failure-depfile";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      # the same failing compile twice: the second is a cache replay when jigd is there. kbuild's
      # -Wp,-MMD,<file>: fixdep reads the depfile even when the compile fails
      run = ''
        mkdir $"($c.out)/share"
        # a fresh key each build: a rerun must not find this build's entries
        let salt = $"-DSALT=(random chars --length 16)"
        # in order. seeded: the failure is first stored by a run without a depfile (nodep), which a
        # run that wants one must not replay
        let plan = [
          [passthrough seeded run];
          ["" false first] ["" false second]
          ["1" false first] ["1" false second]
          ["" true nodep] ["" true first] ["" true second]
        ]
        let runs = ($plan | each {|p|
          rm -f t.d
          let flags = ((if $p.seeded { ["-DSEEDED"] } else { [] }) ++ (if $p.run == nodep { [] } else { ["-Wp,-MMD,t.d"] }))
          let r = (with-env {JIG_PASSTHROUGH: $p.passthrough} { ^cc -Werror -Wunused-variable $salt ...$flags -c t.c -o t.o | complete })
          print -e $r.stderr
          let log = (open --raw $env.JIG_LOG | lines | last | split row "\t")
          $p | merge {status: $r.exit_code, outcome: $log.1, subject: $log.2
                      depfile: (if ("t.d" | path exists) { open --raw t.d } else { null })}
        })
        {cache: $c.cache, runs: $runs} | to json | save $"($c.out)/share/runs.json"
      '';
    }
  ];
  tests.run = false;
}
