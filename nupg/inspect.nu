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

const cache_table = "nupg_schema_cache"

# Return the PostgreSQL tables & columns as a nushell table
#
# Uses Nushell's in-memory sqlite DB ('stor') to cache the schema
export def schema [
  --table-prefix (-t): string = ""
    # Only get tables matching this prefix. Empty string matches everything
]: nothing -> table<table_name: string, columns: table<column_name: string, pg_type: string, is_nullable: bool>> {
  let cache_key = $"($env.PSQL_DB_STRING)/($env.PSQL_SCHEMA)"
  match (
    stor open |
      query db $"select count\(*) from ($cache_table) where key = '($cache_key)'" |
      first | values | first
  ) {
    0 => {
      force-get-schema | flatten -a columns | insert key $cache_key |
        stor insert -t $cache_table
    }
  }
  stor open |
    query db $"select * from ($cache_table)
               where key = '($cache_key)'
               and table_name like '($table_prefix)%'" |
    update is_nullable {$in == 1} |
    group-by table_name --to-table |
    default -e [] | # on empty inputs, group-by always returns an empty _record_
    rename table_name columns
}
