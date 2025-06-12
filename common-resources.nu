use ./lib.nu

# Create a resource corresponding to a file or folder on the file system
#
# Removes the path with 'rm -rf' when it is finalized
export def "mkscoped file" [
  --scope (-s): string # See 'mkscoped' doc
  closure: closure
    # A closure that creates and return a new path, for instance a call to 'mktemp'
]: nothing -> path {
  mkscoped -t file -s $scope $closure {rm -rf $in}
}

# Create a resource corresponding to a nushell job
#
# Kills the job with 'job kill' with it is finalized
export def "mkscoped job" [
  --scope (-s): string # See 'mkscoped' doc
  closure: closure # See 'job spawn doc'
]: nothing -> int {
  mkscoped -t job -s $scope {job spawn $closure} {job kill $in}
}

# Schedule a closure to run at the end of a scope
export def "defer" [
  --scope (-s): string # See 'mkscoped doc'
  closure: closure # Something to run at the end of the scope
    # Will be fed the input to defer
] {
  let x = $in
  mkscoped -t deferred-closure -s $scope {} {$x | do $closure}
}
