use internals.nu *
use ../build.nu
use ../run.nu
use ../pretty.nu 

# Add a query to the store file
export def main [name: string]: string -> nothing {
  let query = $in | pretty format
  let cols = $query | run columns
  # TODO: Don't save if 'run columns failed'
  get-store |
    merge {$name: {query: $query, columns: $cols}} |
    save -f $env.nupg.store
}

# Get the stored queries with their output types
export def list [] {
  [(get-store)] | update cells {get columns} | first 
}

def getq [name] {
  get-store | get $name | get query
}

# Print a stored query
export def show [name: string@complete-stored] {
  getq $name | pretty highlight --name $name
}

def __run [name: string@complete-stored] {
  getq $name | run
}

# Remove a stored query
export def rm [name: string@complete-stored] {
  get-store | reject $name | save -f $env.nupg.store
}

# Run a stored query
export alias run = __run
