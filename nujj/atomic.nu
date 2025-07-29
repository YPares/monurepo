use std log

# Run a nushell closure performing a set of jj operations as atomically
# as possible. Ie. if one operation fails, revert back to the state before
# the closure started.
#
# However, this is not a real DB-like transaction, because it is not
# *isolated*: if you run other jj commands in parallel, they can get intertwined
# with those of the closure (and the effect of those parallel operations
# would be cancelled along if the closure fails, which is probably what you
# want anyway in such a case). Note that this should be much improved when
# https://github.com/jj-vcs/jj/pull/4457 lands.
#
# Long story short: don't run several of these in parallel for now, please.
#
# Also, it doesn't make the closure atomic with respect to 'jj undo', which
# will only undo the *last* jj command executed by the closure. This is why
# we print the 'jj op restore' command that you can run later to undo the
# whole closure.
#
# Nesting calls to 'atomic' is allowed. In such a case, the inner calls will
# just be no-ops.
export def main [
  --name (-n): string = "anonymous-atomic"
    # A name to show in the nushell logs
  closure: closure
    # A set of jj operations to run atomically
] {
  if ($env.nujj?.atomic-ongoing? == true) {
    log debug $"($name): Already in an atomic block"
    $in | do $closure
  } else {
    let init_op = ^jj op log --no-graph -n1 -T "id.short()" 
    let res = try {
      log debug $"($name): Starting atomic block at op ($init_op)"
      let res = $in | do {
        $env.nujj.atomic-ongoing = true
        $in | do $closure
      }
      let final_op = ^jj op log --no-graph -n1 -T "id.short()" 
      if $final_op == $init_op {
        log debug $"($name): Atomic block finished. Remained at op ($init_op)"
      } else {
        log debug $"($name): Atomic block finished. Now at op ($final_op)"
        log info $"($name): Several jj commands ran. To undo, use '(ansi yellow)jj op restore ($init_op)(ansi reset)'"
      }
      {ok: $res}
    } catch {|exc|
      log error $"($name): Atomic block failed. Reverting to op ($init_op)"
      ^jj op restore $init_op
      {exc: $exc}
    }
    match $res {
      {ok: $x} => { $x }
      {exc: $exc} => { error make $exc.raw }
    }
  }
}


