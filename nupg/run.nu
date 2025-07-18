# A recursive version of 'update' than updates several columns
def run-updates [
  updates: list<list> # A list of (string, closure) tuples
] {
  match $updates {
    [] => {
      $in
    }
    [[$column $closure] ..$rest] => {
      $in | update $column $closure | run-updates $rest
    }
  }
}

# Run an SQL statement without performing any of the column conversion
export def raw-run []: string -> list<any> {
  ^psql $env.PSQL_DB_STRING? --csv | from csv
}

# Get the columns and types returned by a query
export def columns [
  --file (-f): path # Read SQL statement from a file instead
]: [
  string -> table<column: string, type: string>
  nothing -> table<column: string, type: string>
] {
  let query = if $file != null {
    open --raw $file
  } else {$in}
  $'($query) \gdesc' | raw-run | rename column pg_type
}

# Pipe in a PostgreSQL SELECT query to get its result as a nushell table,
# converting the columns to Nushell types along the way, using the conversion
# functions defined in $env.nupg.conversions
#
# Will use $env.PSQL_DB_STRING as the connection string of the database
# to connect to
export def main [
  --file (-f): path # Read SQL statement from a file instead
  --verbose (-v) # Print the query
]: [
  string -> list<any>
  nothing -> list<any>
] {
  let query = if $file != null {
    open --raw $file
  } else if ($in | describe) == "nothing" {
    error make {msg: "nupg: Either feed a query as input or use --file"}      
  } else {$in}
  let types = $query | columns
  let conversions = $types |
    join --left ($env.nupg.conversions | flatten pg_type) pg_type |
    select column pg_convert? nu_convert?

  # We apply the pg_convert in-query conversions:
  let pg_conversions = $conversions | where pg_convert? != null
  let query = if ($pg_conversions | is-empty) {
    $query
  } else {
    let passthrough_cols = $conversions |
      where pg_convert? == null |
      get column | each {$'"($in)"'}
    let converted_cols = $pg_conversions | each {|c|
        $'($c.column | do $c.pg_convert) as ($c.column)'
      }
    $"select ($passthrough_cols ++ $converted_cols | str join ',') from \(($query))"
  }

  # We run the query and apply the nu_convert post-query conversions:
  let nu_conversions = $conversions |
    where nu_convert? != null |
    each {|c| [
      $c.column
      {||
        let x = $in
        try {$x | do $c.nu_convert} catch {$x}
      }
    ]}
  if $verbose {
    print $query
  }
  $query | raw-run | run-updates $nu_conversions
}
