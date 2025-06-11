use std log

# Define a resource scope, ie. a section of code at the end of which
# all resources acquired during the block will be deleted.
# Resources will be deleted in the inverse order in which they were acquired.
#
# Scopes can be nested within one another. Resources are by default attributed
# to the innermost scope.
export def --env define [
  --prefix (-p): string
    # Optionally add a prefix to the key given to the closure that will identify this scope
  fn: closure
    # Will be run with a string key as an argument. Will be fed scope's pipeline input
] {
  let scope_key = $"(if ($prefix != null) {$'($prefix)-'} else {''})(random chars)"
  let prev_innermost = $env.rescope.innermost?
  $env.rescope.innermost = $scope_key
  $env.rescope.scopes = $env.rescope.scopes? | default {} | insert $scope_key []
  let res = try {
    log debug $"Beginning of scope '($scope_key)'"
    $in | do --env $fn scope_key | {ok: $in}
  } catch {|exc|
    {exc: $exc}
  }
  let finalizers = $env.rescope.scopes | get $scope_key
  $env.rescope.scopes = $env.rescope.scopes | reject $scope_key
  $env.rescope.innermost = $prev_innermost
  for fin in $finalizers {
    do --env $fin
  }
  log debug $"End of scope '($scope_key)'"
  match $res {
    {ok: $x} => { $x }
    {exc: $exc} => { error make $exc.raw }
  }
}

# Create a scoped resource.
#
# Will return the return value of 'acquire'
export def --env new [
  --scope-key (-k): string
    # Which scope to attribute the resource to. By default it will be the innermost scope
  acquire: closure
    # A closure to create the resource. Will be fed resource's pipeline input
  finalize: closure
    # A closure to clean up the resource. Will be fed as input whatever 'acquire' returns
] {
  if ($env.rescope.innermost? == null) {
    error make {msg: "'resource' cannot be called here, we are not within a 'scope'"}
  }
  let scope_key = $scope_key | default $env.rescope.innermost
  if ($env.rescope.scopes has $scope_key) {
    let res = $in | do --env $acquire
    let res_id = try { $"($res)" } catch { $"unprintable-(random chars)" }
    log debug $"In scope '($scope_key)': ($res_id) acquired"
    $env.rescope.scopes = $env.rescope.scopes | update $scope_key {prepend {
      try {
        $res | do --env $finalize
        log debug $"In scope '($scope_key)': ($res_id) finalized"
      } catch {|exc|
        log error $"In scope '($scope_key)': could not finalize ($res_id): ($exc)"
      }
    }}
  } else {
    error make {msg: $"Scope '($scope_key)' does not exist"}
  }
}
