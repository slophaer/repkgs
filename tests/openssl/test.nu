# OpenSSL's default configuration is the machine's OPENSSLDIR/openssl.cnf when there is one, else
# the package's own etc/ssl/openssl.cnf next to the loaded libcrypto, so `openssl req` works where
# /etc/ssl has none (a build). OPENSSL_CONF still wins; OPENSSLDIR stays the machine's /etc/ssl
use checks.nu *

let openssl = $"($env.pkg)/bin/openssl"
let dir = (^env -i $openssl version -d | str trim)
assert $"OPENSSLDIR is the machine's: ($dir)" ($dir == 'OPENSSLDIR: "/etc/ssl"')

let args = "req -verbose -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=t -days 1"
def used []: string -> string { parse -r 'Using configuration from (?<f>\S+)' | get -o f.0 | default "" }
cd $env.NIX_BUILD_TOP

# no /etc/ssl/openssl.cnf here: the package's own
let req = (^env -i $openssl ...($args | split row " ") -keyout k.pem -out c.pem | complete)
assert $"req works with no OPENSSL_CONF: ($req.stdout)($req.stderr)" ($req.exit_code == 0)
let own = ($req.stdout + $req.stderr | used)
assert $"without the machine's, the configuration is the package's: ($own)" (($own | path expand) == ($"($env.pkg)/etc/ssl/openssl.cnf" | path expand))

# the machine's /etc/ssl/openssl.cnf, when there is one, in a private mount namespace
let tool = {|n| which -a $n | where type == external | get path.0 }
let cnf = $"($env.pkg)/etc/ssl/openssl.cnf"
let script = $"(do $tool mount) -t tmpfs none /etc && (do $tool mkdir) /etc/ssl && (do $tool cp) ($cnf) /etc/ssl/openssl.cnf && exec (do $tool env) -i ($openssl) ($args) -keyout k3.pem -out c3.pem"
let sys = (^env -i (do $tool unshare) -rm (do $tool sh) -c $script | complete)
let machine = ($sys.stdout + $sys.stderr | used)
assert $"with the machine's, the configuration is /etc/ssl/openssl.cnf: ($machine) ($sys.stderr)" ($sys.exit_code == 0 and $machine == "/etc/ssl/openssl.cnf")

let env_conf = (^env -i OPENSSL_CONF=/dev/null $openssl ...($args | split row " ") -keyout k2.pem -out c2.pem | complete)
assert $"OPENSSL_CONF still wins: ($env_conf.stdout)($env_conf.stderr)" ($env_conf.exit_code == 0 and ($env_conf.stdout + $env_conf.stderr | str contains "Using configuration from /dev/null"))
done
