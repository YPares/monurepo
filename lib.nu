use std log

# We start a job that will maintain stacks of closures,
# each one indexed by some arbitrary string key
def run-closure-store [] {
  log debug $"Closure store \(job (job id)): start"
  mut closure_store = {}
  loop {
    match (job recv) {
      {under: $key, register: $cls} => {
        $closure_store = $closure_store |
          upsert $key {default [] | prepend $cls}
      }
      {run: $key, stop: $should_stop, reply-to: $job_id} => {
        try {
          for cls in ($closure_store | get $key) {
            try {
              do $cls
            } catch {|exc|
              log error $"Closure store \(job (job id)): some closure under key ($key) failed with: ($exc.msg)"
            }
          }
          $closure_store = $closure_store | reject $key
        } catch {
          log debug $"Closure store \(job (job id)): no closures stored under key ($key)"
        }
        if $should_stop {
          if ($closure_store | is-empty) {
              log debug $"Closure store \(job (job id)): end"
          } else {
              log error $"Closure store \(job (job id)): stopping with unexecuted closures under key\(s) ($closure_store | columns)"
          }
        }
        if $job_id != null {
          "done" | job send $job_id
        }
        if $should_stop {
          break
        }
      }
    }
  }
}

# Define a resource scope, ie. a section of code at the end of which
# all resources acquired during the block will be deleted.
# Resources will be deleted in the inverse order in which they were acquired.
#
# Scopes can be nested within one another. Resources are by default attributed
# to the innermost scope.
export def rescope [
  --prefix (-p): string
    # Optionally add a prefix to the key that will identify this scope
  --async
    # When the scope ends, will not wait for all closures to be completed
    # before continuing
  fn: closure
    # Will be fed rescope's pipeline input.
    # Will be executed with a string key as an argument, to be used as the
    # '--scope' argument for subsequent 'mkscoped' calls
] {
  let controls_closure_store_job = if $env.rescope?.closure-store-job-id? == null {
    $env.rescope.closure-store-job-id = job spawn --tag "closure-store" { run-closure-store }
    true
  } else { false }

  let scope_key = $"(if ($prefix != null) {$'($prefix)-'} else {''})(random chars)"
  $env.rescope.scopes = $env.rescope?.scopes? | default [] | prepend $scope_key

  let res = try {
    log debug $"Scope ($scope_key): start"
    $in | do $fn $scope_key | {ok: $in}
  } catch {|exc|
    log debug $"Scope ($scope_key): exception caught. Cleaning up early"
    {exc: $exc}
  }

  {
    run: $scope_key
    stop: $controls_closure_store_job
    reply-to: (if (not $async) {(job id)})
  } | job send $env.rescope.closure-store-job-id
  if (not $async) {
    job recv
  }

  log debug $"Scope ($scope_key): end"
  match $res {
    {ok: $x} => { $x }
    {exc: $exc} => {
      # We rethrow:
      error make $exc.raw
    }
  }
}

# Create a scoped resource.
#
# Will return the return value of 'acquire'
export def mkscoped [
  --scope (-s): string
    # Which scope to attribute the resource to. By default it will be the innermost scope
  --tag (-t): string
    # An optional tag to help identify the resource activity in the logs
  acquire: closure
    # A closure to create the resource. Will be fed mkscoped's pipeline input
  finalize: closure
    # A closure to clean up the resource. Will be fed as input whatever 'acquire' returns
] {
  if ($env.rescope?.scopes? | is-empty) {
    error make {msg: "'mkscoped' cannot be called here: we are not in a closure run by 'rescope'"}
  }
  let scope_key = $scope | default ($env.rescope.scopes | first)
  let tag = if $tag != null {$"[($tag)] "} else {""}
  if ($env.rescope.scopes has $scope_key) {
    let res = $in | do $acquire
    let res_id = try { $"($res)" } catch { $"unprintable" }
    log debug $"Scope ($scope_key): ($tag)($res_id) acquired"
    {
      under: $scope_key
      register: {
        $res | do $finalize
        log debug $"Scope ($scope_key): ($tag)($res_id) finalized"
      }
    } | job send $env.rescope.closure-store-job-id
  } else {
    error make {msg: $"No scope with key '($scope_key)' exists"}
  }
}
