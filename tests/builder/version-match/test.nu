# finish.nu's version-found: the pinned version must appear as a whole version in a program's output
use finish.nu [version-found]
use checks.nu *

def ok [what: string, text: string, want: string] { assert $"found: ($what)" (version-found $text $want) }
def no [what: string, text: string, want: string] { assert $"not found: ($what)" (not (version-found $text $want)) }

# a version that is part of a longer one
no "digit before" "bc 11.2" "1.2"
no "digit after" "bc 1.20" "1.2"
no "another component after" "bc 1.2.3" "1.2"
no "another component before" "bc 0.1.2" "1.2"
no "two more components" "1.2.3.4" "1.2"
no "date glued on" "ncurses 6.6.20251230" "6.6"
no "only the longer one in several lines" "tool 11.2\nlib 1.20\nabi 1.2.3\n" "1.2"
no "dotted pin inside a longer pin" "x 1.2.3" "2.3"
no "prefix of a pin" "x 1.2" "1.2.3"

# the version as the program writes it
ok "alone" "1.2" "1.2"
ok "newline after" "1.2\n" "1.2"
ok "name and version" "jq-1.8.2" "1.8.2"
ok "v prefix" "v24.21.0" "24.21.0"
ok "go prefix" "go version go1.27.1 linux/amd64" "1.27.1"
ok "sentence end" "this is version 1.2." "1.2"
ok "comma after" "curl 8.22.0, libcurl" "8.22.0"
ok "parenthesis" "bash (5.3)" "5.3"
ok "pin with a letter" "tzdata 2026d" "2026d"
ok "release suffix kept in the pin" "libevent 2.1.13-stable" "2.1.13-stable"
ok "build number in the pin" "(build 25.0.4.1+1)" "25.0.4.1+1"
ok "git version in the pin" "gn 0.0~git20261103.2e3ba823" "0.0~git20261103.2e3ba823"
ok "release candidate suffix of the program" "1.2-rc1" "1.2"
ok "a letter after" "bash 5.3p20" "5.3"
ok "two lines, the second whole" "api 11.2\nversion 1.2\n" "1.2"
ok "glued one first, whole one after" "1.20 1.2" "1.2"
ok "in the middle of a line" "foo 1.2 bar" "1.2"
ok "stderr text after stdout text" "x\n1.2" "1.2"
ok "regex characters in the pin" "v1.2+git" "1.2+git"
no "a dot is not any character" "1x2" "1.2"
no "a plus is not a quantifier" "1.222" "1.2+"
done
