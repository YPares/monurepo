use store/internals.nu *

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

# Convert $in into a string that can be inlined into postgres queries,
# via its JSON representation.
# The produced string is usable either as JSONB or as some PostgreSQL
# atomic type
export def to-quoted-json []: any -> string {
  to json --raw --serialize |
  str replace -ra "^\"|\"$" "" |
  str replace -a "'" "''" |
  $"'($in)'"
}

export def --wrapped psql [...args] {
  (
    ^psql
      ...(if $env.nupg.user_configs.psql {[]} else {[--no-psqlrc]})
      $env.PSQL_DB_STRING
      ...$args
  )
}

# Run an SQL statement without performing any output conversion
export def raw [
  --variables (-v): record = {}
    # Values to use to replace the :foo, :"foo", :'foo' variables in the query
  ...params: any
    # Values to use to replace the $1, $2, $3, etc. placeholders
    # in the query.
]: string -> list<any> {
  [
    ...($variables |
      transpose key val |
      each {|var|
        $"\\set ($var.key) ($var.val | to-quoted-json)"
      })
    $in
    ...(match $params {
      [] => []
      _ => [(
        " \\bind " + ($params | each {to-quoted-json} | str join ' ')
      )]
    })
  ] |
    str join "\n" |
    tee {std log debug $"Running: ($in)"} |
      psql --csv --pset=null=(char bel) |
      from csv |
      update cells {if ($in == (char bel)) {null} else {$in}}
}

# Get the columns and types returned by a query
#
# Will read the db connection string from $env.PSQL_DB_STRING
export def desc [
  --file (-f): path # Read SQL statement from a file instead
  --no-stored-queries (-S) # Do not use stored queries
  --variables (-v): record = {} 
    # Values to use to replace the :foo, :"foo", :'foo' variables in the query.
    # Contrary to positional placeholders ($1, $2 etc.), these need to be
    # set for the query to be valid PostgreSQL
]: [
  string -> table<column_name: string, pg_type: string>
  nothing -> table<column_name: string, pg_type: string>
] {
  let query = if $file != null {
    open --raw $file
  } else {$in} |
    wrap-with-stored --no-stored-queries=$no_stored_queries
  
  let cols = $'($query) \gdesc' | raw --variables=$variables | rename column_name pg_type
  if ($cols | is-empty) {
    error make -u {
      msg: $"psql could not describe the result column types of\n($query)"
    }
  } else {
    $cols
  }
}

# Pipe in a PostgreSQL query to get its result as a nushell table,
# converting the columns to Nushell types along the way, using the conversion
# functions defined in $env.nupg.conversions.pg_to_nu
#
# Will read the db connection string from $env.PSQL_DB_STRING
export def main [
  --file (-f): path # Read SQL statement from a file instead
  --no-stored-queries (-S) # Do not use stored queries
  --variables (-v): record = {}
    # Values to use to replace the :foo, :"foo", :'foo' variables in the query
  ...params: any
    # Values to use to replace the $1, $2, $3, etc. placeholders
    # in the query.
]: [
  string -> list<any>
  nothing -> list<any>
] {
  let query = if $file != null {
    open --raw $file
  } else if ($in | describe) == "nothing" {
    error make {msg: "nupg: Either feed a query as input or use --file"}      
  } else {
    $in
  } |
    wrap-with-stored --no-stored-queries=$no_stored_queries

  # We get the types returned by the query:
  let cols = $query | desc --variables=$variables --no-stored-queries

  let conversions = $cols |
    join --left ($env.nupg.conversions.pg_to_nu | flatten pg_type) pg_type |
    select column_name pg_convert? nu_convert?

  # We apply the pg_convert in-query conversions:
  let pg_conversions = $conversions | where pg_convert? != null
  let query = if ($pg_conversions | is-empty) {
    $query
  } else {
    let passthrough_cols = $conversions |
      where pg_convert? == null |
      get column_name |
      each {$'"($in)"'}
    let converted_cols = $pg_conversions | each {|c|
      $'($c.column_name | do $c.pg_convert) as ($c.column_name)'
    }
    $"select ($passthrough_cols ++ $converted_cols | str join ',') from \(($query))"
  }

  # We run the query and apply the nu_convert post-query conversions:
  let nu_conversions = $conversions |
    where nu_convert? != null |
    each {|c| [
      $c.column_name
      {||
        let x = $in
        try {$x | do $c.nu_convert} catch {$x}
      }
    ]}
  $query | raw --variables=$variables ...$params | run-updates $nu_conversions
}
