{ package }:
package {
  name = "test-cc-incbin";
  version = "1";
  source = ./src;
  phases = [
    {
      name = "build";
      # `.incbin` and `.include` read a file the depfile does not name (clang writes `t.o: t.S`), so
      # the object depends on bytes the cache key never sees. Each case compiles the same source
      # twice, in the same directory with the same arguments, and only the data file differs
      # between the runs. `args` is a command line that carries the directive (-D macro)
      run = ''
        mkdir $"($c.out)/share"
        let cases = [
          [name src file args];
          [direct t.S data.bin []]
          [included viainc.S data.bin []]
          [inline inline.c data.bin []]
          [macro macro.S data.bin [-DEMBED=.incbin]]
          [asminclude incl.S data.inc []]
          [asminclude-inline inclinline.c data.inc []]
          [missing t.S data.bin []]
        ]
        let runs = ($cases | each {|k|
          # the first run holds AAAA, the second BBBB. "missing": no file at first, then BBBB
          let data = (if $k.name == missing { [null BBBB] } else { [AAAA BBBB] })
          # a fresh key for each case and build: neither a rerun nor another case may find its entries
          let salt = $"-DSALT=(random chars --length 16)"
          $data | enumerate | each {|d|
            rm -f data.bin data.inc t.o
            # data.inc is assembly text, data.bin raw bytes
            if $d.item != null { (if $k.file == data.inc { $".ascii \"($d.item)\"\n" } else { $d.item }) | save $k.file }
            let r = (^cc $salt ...$k.args -c $k.src -o t.o | complete)
            print -e $r.stderr
            let log = (open --raw $env.JIG_LOG | lines | last | split row "\t")
            {case: $k.name, run: ($d.index + 1), data: $d.item, status: $r.exit_code, outcome: $log.1
              has_a: (if ("t.o" | path exists) { (open --raw t.o | bytes index-of 0x[41414141]) >= 0 } else { false })
              has_b: (if ("t.o" | path exists) { (open --raw t.o | bytes index-of 0x[42424242]) >= 0 } else { false })}
          }
        } | flatten)
        {cache: $c.cache, runs: $runs} | to json | save $"($c.out)/share/runs.json"
      '';
    }
  ];
  tests.run = false;
}
