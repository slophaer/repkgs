use checks.nu *
let declared = ($env.declared | from json | sort)
let inventory = (open ($env.pkg | path join exports.json) | get bin | sort)
assert "elfutils declares every installed tool, and no absent tool" ($declared == $inventory)
done
