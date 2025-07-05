use . *
use std log

log set-level 0 # activate debug logs

rescope -p sc1 {|sc1|
  # We open a temp folder whose finalization (removal)
  # is scheduled at the end of this scope (closure):
  let path = mkscoped file -s $sc1 { mktemp --directory }

  # We schedule to print "Bye!" at the end of this closure:
  "Bye!" | defer -s $sc1 { print $in }

  rescope -p sc2 {|sc2|
    # Here, no `-s` is given: finalizers are by defaut attached to the
    # innermost scope. So here, sc2: 
    let job1 = mkscoped job { sleep 10sec }
    # But we can also target the outer scope:
    let job2 = mkscoped job -s $sc1 { sleep 10sec }

  } # End of sc2: $job1 gets killed

} # End of sc1: $job2 gets killed, then "Bye!" is printed, then $path gets deleted
  # (Resources are always finalized in the order inverse to their creation)
