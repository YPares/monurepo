use ./lib.nu

# Create a resource corresponding to a file or folder on the file system
#
# Removes the path with 'rm -rf' when it is finalized
export def --env "new file" [
  --scope-key (-k): string
    # See 'resource' doc
  make_path: closure
    # A closure that creates and return a new path, for instance a call to 'mktemp'
]: nothing -> path {
  new -k $scope_key $make_path {rm -rf $in}
}

# Create a resource corresponding to a nushell job
#
# Kills the job with 'job kill' with it is finalized
export def --env "new job" [
  --scope-key (-k): string
    # See 'resource' doc
  closure: closure
    # See 'job spawn doc'
]: nothing -> int {
  new -k $scope_key {job spawn $closure} {job kill $in}
}
