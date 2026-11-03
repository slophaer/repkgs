# Test that launcher env follows exports.propagate transitively
# Package A depends on B. B propagates C. C exports env.FOO and env.C_MARKER.
# The test passes if A's launch record contains FOO, C_MARKER, and B_MARKER.

use checks.nu *

# Read A's launch record
let record_path = $"($env.pkg)/bin/.test-propagate-a.launch"
assert "launch record exists" ($record_path | path exists)
let record = (open $record_path | from json)

# C exports FOO and C_MARKER - they must reach A via B's propagate
assert "FOO from C via propagate" ($record.env?.FOO? != null)
assert "C_MARKER from C via propagate" ($record.env?.C_MARKER? != null)

# B exports B_MARKER directly
assert "B_MARKER from B directly" ($record.env?.B_MARKER? != null)

# Values must use `default` semantics (user env wins)
assert "FOO uses default semantics" ($record.env.FOO.default? != null)
assert "C_MARKER uses default semantics" ($record.env.C_MARKER.default? != null)
assert "B_MARKER uses default semantics" ($record.env.B_MARKER.default? != null)

# Precedence: a direct dependency beats a propagated one, and among direct dependencies the last
# declared one wins (A declares B then D)
assert "direct dependency beats propagated" ($record.env.PREC_DIRECT.default == "from-b")
assert "last declared direct dependency wins" ($record.env.PREC_ORDER.default == "from-d")

done
