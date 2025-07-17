export-env {
  # By default, will connect on local UNIX socket to the 'postgres' database
  $env.PSQL_DB_STRING = "postgresql://%2Fvar%2Frun%2Fpostgresql/postgres"

  $env.nupg.conversions = [
    [pg_type convert];
    [[json jsonb]
      {from json}]
    [[timestamp "timestamp with time zone"]
      {into datetime}]
  ]
}

def run []: string -> list<any> {
  ^psql $env.PSQL_DB_STRING? --csv | from csv
}

# Pipe in a PostgreSQL query to get its result as a nushell table, converting the columns
# to Nushell types along the way
#
# Will use $env.PSQL_DB_STRING as the connection string of the database
# to connect to
export def main [
  --file (-f): path # Read SQL statement from a file instead
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
  let convs = $types | join ($env.nupg.conversions | flatten pg_type) type pg_type | select column convert
  $query | run | each {
    transpose column value | join --left $convs column | each {|cell|
      let val = if $cell.convert? == null {
        $cell.value
      } else {
        try {
          $cell.value | do $cell.convert
        } catch {
          $cell.value
        }
      }
      {column: $cell.column, value: $val}
    } | transpose -rd
  }
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
  $'($query) \gdesc' | run | rename column type
}
