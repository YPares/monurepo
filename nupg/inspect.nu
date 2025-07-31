use std-rfc/kv *

use run.nu

def force-get-schema [
]: nothing -> table<table_name: string, columns: table<column_name: string, pg_type: string, is_nullable: bool>> {
  $"select table_name, jsonb_agg\(jsonb_build_object\(
      'column_name', column_name,
      'pg_type', data_type,
      'is_nullable', case when is_nullable = 'YES' then true else false end
    ))
   from information_schema.columns
   where table_schema = '($env.PSQL_SCHEMA)'
   group by table_name" |
    run --no-stored-queries |
    rename table_name columns
}

# Return the PostgreSQL tables & columns as a nushell table
#
# Uses Nushell's in-memory sqlite DB ('stor') to cache the schema
export def schema [
  --table-prefix (-t): string = ""
    # Only get tables matching this prefix. Empty string matches everything
]: nothing -> table<table_name: string, columns: table<column_name: string, pg_type: string, is_nullable: bool>> {
  let cache_key = $"nupg_($env.PSQL_DB_STRING)_($env.PSQL_SCHEMA)"
  match (kv get $cache_key) {
    null => {
      force-get-schema | kv set $cache_key --return value
    }
    $s => $s
  } | where table_name =~ $table_prefix
}

# List available databases
export def databases []: nothing -> table {
  "\\list" | run raw |
    rename -b {str downcase | str replace " " "_"}
}

# Show information about current connection
export def main []: nothing -> string {
  "\\conninfo" | run psql | collect
}
