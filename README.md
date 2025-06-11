# rescope.nu

Scoped resources for Nushell.

Experimental.

## Example

```nu
use rescope.nu *
use std log

log set-level 0 # activate debug logs

rescope {|sc1|
  let path = mkscoped file -s $sc1 { mktemp --directory }

  rescope {|sc2|

    let job1 = mkscoped job { sleep 10sec }
               # No -s given: we use the innermost scope
    let job2 = mkscoped job -s $sc1 { sleep 10sec }

  } # Here: job1 gets killed

} # Here: job2 gets killed, then path gets deleted
```
