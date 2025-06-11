use std log

# We start a job that will maintain a mutable set of finalizers,
# indexed per scope key
def rescope-job [] {
  log debug $"rescope-job \(id (job id)) started"
  mut finalizers = {}
  mut job_asking_to_stop = -1 # job ids are positive or null
  while $job_asking_to_stop < 0 {
    match (job recv) {
      {add: $fin, to: $key} => {
        $finalizers = $finalizers |
          upsert $key {default [] | prepend $fin}
      }
      {exit: $key} => {
        for fin in ($finalizers | get -i $key) {
          do $fin
        }
        $finalizers = $finalizers | reject -i $key
      }
      {stop: $job_id} => {
        $job_asking_to_stop = $job_id
      }
    }
  }
  match $finalizers {
    {} => {
      log debug $"rescope-job \(id (job id)) stopped gracefully"
    }
    _ => {
      log error $"rescope-job \(id (job id)) stopped with unexecuted finalizers for scopes ($finalizers | columns)"
    }
  }
  "ok" | job send $job_asking_to_stop
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
  fn: closure
    # Will be fed rescope's pipeline input.
    # Will be executed with a string key as an argument, to be used as the
    # '--scope' argument for subsequent 'mkscoped' calls
] {
  let controls_rescope_job = if $env.rescope?.job-id? == null {
    $env.rescope.job-id = job spawn --tag "rescope-job" { rescope-job }
    true
  } else { false }

  let scope_key = $"(if ($prefix != null) {$'($prefix)-'} else {''})(random chars)"
  $env.rescope.scopes = $env.rescope?.scopes? | default [] | prepend $scope_key

  let res = try {
    log debug $"Beginning of scope '($scope_key)'"
    $in | do $fn $scope_key | {ok: $in}
  } catch {|exc|
    log debug $"Scope ($scope_key): exception caught. Cleaning up early"
    {exc: $exc}
  }

  {exit: $scope_key} | job send $env.rescope.job-id

  if $controls_rescope_job {
    {stop: (job id)} | job send $env.rescope.job-id
    # We wait until the rescope-job stops gracefully and signals us:
    job recv
  }
  log debug $"End of scope '($scope_key)'"
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
  acquire: closure
    # A closure to create the resource. Will be fed mkscoped's pipeline input
  finalize: closure
    # A closure to clean up the resource. Will be fed as input whatever 'acquire' returns
] {
  if ($env.rescope?.scopes? | is-empty) {
    error make {msg: "'mkscoped' cannot be called here, we are not within a 'rescope'"}
  }
  let scope_key = $scope | default ($env.rescope.scopes | first)
  if ($env.rescope.scopes has $scope_key) {
    let res = $in | do $acquire
    let res_id = try { $"($res)" } catch { $"unprintable-(random chars)" }
    log debug $"In scope '($scope_key)': ($res_id) acquired"
    {
      add: {
        try {
          $res | do $finalize
          log debug $"In scope ($scope_key): ($res_id) finalized"
        } catch {|exc|
          log error $"In scope ($scope_key): could not finalize ($res_id): ($exc)"
        }
      }
      to: $scope_key
    } | job send $env.rescope.job-id
  } else {
    error make {msg: $"Scope '($scope_key)' does not exist"}
  }
}
