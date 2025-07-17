export-env {
  # By default, will connect on local UNIX socket to the 'postgres' database
  $env.PSQL_DB_STRING = "postgresql://%2Fvar%2Frun%2Fpostgresql/postgres"

  $env.nupg = {
    # The table of conversions to perform, depending on the type of the rows
    # of the query detected by psql. Each conversion is composed of two parts:
    # 
    # - an in-query part (pg_convert):
    #     a postgres wrapper applied to columns of this type
    # - a post-query part (nu_convert):
    #     a nushell closure applied to returned values transformed
    #     by the in-query conversion
    # 
    # Any of these two parts can be null, in which case the value will just pass
    # through untransformed.
    #
    # See 'default-conversions' to check how this conversion table should be laid out
    conversions: (default-conversions)
  }
}

# The default set of conversions performed by nupg
#
# You can use this as a base to which to add your own extra conversions
export def default-conversions [
]: nothing -> table<pg_type: oneof<string,list<string>>, pg_convert: oneof<closure,nothing>, nu_convert: oneof<closure,nothing>> {
  [
    [pg_type pg_convert nu_convert];

    [["text[]" "integer[]"]
      {$"array_to_json\(($in))"}
      {from json}
    ]
    [[json jsonb]
      null
      {from json}]
    [[timestamp "timestamp with time zone"]
      null
      {into datetime}]
  ]
}

def run-psql []: string -> list<any> {
  ^psql $env.PSQL_DB_STRING? --csv | from csv
}

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

# Pipe in a PostgreSQL query to get its result as a nushell table, converting the columns
# to Nushell types along the way
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
  $query | run-psql | run-updates $nu_conversions
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
  $'($query) \gdesc' | run-psql | rename column pg_type
}
