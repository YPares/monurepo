use run.nu

# Return the wanted schema as a nushell table
export def schema [
  schema: string = "public" # The schema to read
]: nothing -> table<table_name: string, columns: table<column_name: string, pg_type: string, is_nullable: bool>> {
  $"select table_name, jsonb_agg\(jsonb_build_object\(
      'column_name', column_name,
      'pg_type', data_type,
      'is_nullable', case when is_nullable = 'YES' then true else false end
    ))
   from information_schema.columns
   where table_schema='($schema)'
   group by table_name" | run | rename table_name columns
}
