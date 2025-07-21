use run.nu

# Return the PostgreSQL tables & columns as a nushell table
export def schema [
  --table-prefix (-t): string = ""
    # Only query tables matching this prefix. Empty string matches everything
  --schema (-s): string # The schema to target. $env.PSQL_SCHEMA by default
]: nothing -> table<table_name: string, columns: table<column_name: string, pg_type: string, is_nullable: bool>> {
  let schema = if $schema != null {
    $schema
  } else {$env.PSQL_SCHEMA}

  $"select table_name, jsonb_agg\(jsonb_build_object\(
      'column_name', column_name,
      'pg_type', data_type,
      'is_nullable', case when is_nullable = 'YES' then true else false end
    ))
   from information_schema.columns
   where table_schema = '($schema)'
     and table_name like '($table_prefix)%'
   group by table_name" |
    run --no-stored-queries |
    rename table_name columns
}
