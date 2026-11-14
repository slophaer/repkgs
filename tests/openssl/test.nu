# OpenSSL's default configuration is the package's own etc/ssl/openssl.cnf, found next to the
# loaded libcrypto: no build host's /etc/ssl/openssl.cnf is read, and `openssl req` needs no
# OPENSSL_CONF. OPENSSLDIR, where the certificates are, stays the machine's /etc/ssl
use checks.nu *

let openssl = $"($env.pkg)/bin/openssl"
let dir = (^env -i $openssl version -d | str trim)
assert $"OPENSSLDIR is the machine's: ($dir)" ($dir == 'OPENSSLDIR: "/etc/ssl"')

cd $env.NIX_BUILD_TOP
let req = (^env -i $openssl req -verbose -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=t -days 1 -keyout k.pem -out c.pem | complete)
assert $"req works with no OPENSSL_CONF: ($req.stdout)($req.stderr)" ($req.exit_code == 0)
let used = ($req.stdout + $req.stderr | parse -r 'Using configuration from (?<f>\S+)' | get -o f.0 | default "")
assert $"the configuration is the package's: ($used)" (($used | path expand) == ($"($env.pkg)/etc/ssl/openssl.cnf" | path expand))

let own = (^env -i OPENSSL_CONF=/dev/null $openssl req -verbose -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=t -days 1 -keyout k2.pem -out c2.pem | complete)
assert $"OPENSSL_CONF still wins: ($own.stdout)($own.stderr)" ($own.exit_code == 0 and ($own.stdout + $own.stderr | str contains "Using configuration from /dev/null"))
done
