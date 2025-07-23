use internals.nu *
use ../build.nu
use ../run.nu
use ../pretty.nu 

# Add a query to the store file
export def main [name: string]: string -> nothing {
  let query = $in | pretty format
  let cols = $query | run columns
  get-store |
    merge {$name: {query: $query, columns: $cols}} |
    save -f $env.nupg.store
}

# Get the stored queries with their output types
export def list [] {
  stored-types
}

def getq [name] {
  get-store | get $name | get query
}

# Print a stored query
export def show [
  name: string@complete-stored
  --wrapped (-w) # Wrap the query with the other stored queries 
] {
  if $wrapped {
    $"select * from ($name)" | wrap-with-stored | pretty format | pretty highlight --name $name
  } else {
    getq $name | pretty highlight --name $name
  }
}

# Remove a stored query
export def rm [name: string@complete-stored] {
  get-store | reject $name | save -f $env.nupg.store
}
