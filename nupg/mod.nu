export use run.nu [
  main
  describe
]
export use build.nu [
  main
  recordset
]
export use inspect.nu
export use pretty.nu
export use store

use build.nu [
  complete-build
]

export-env {
  # By default, will connect on local UNIX socket to the 'postgres' database
  $env.PSQL_DB_STRING = "postgresql://%2Fvar%2Frun%2Fpostgresql/postgres"

  # Which schema to target when querying table & column schema for autocompletion
  $env.PSQL_SCHEMA = "public"

  $env.nupg = {
    conversions: {
      # The table of conversions to perform on query results,
      # depending on the type of the rows of the query detected by psql.
      #
      # Each conversion is composed of two parts:
      # 
      # - an in-query part (pg_convert):
      #     a postgres wrapper applied to columns of this type
      # - a post-query part (nu_convert):
      #     a nushell closure applied to returned values transformed
      #     by the in-query conversion
      # 
      # Any of these two parts can be null, in which case the value will just pass
      # through untransformed.
      pg_to_nu: (default-pg-to-nu-conversions),

      # The table of conversions to perform on the nushell data that should
      # be injected into queries (via the 'recordset' command)
      #
      # Any nushell datatype that is not present in this conversions table
      # will be mapped to 'JSONB'
      nu_to_pg: (default-nu-to-pg-conversions)
    } 

    # Whether to read the user's config files for the tools used internally
    user_configs: {
      psql: true  # ~/.psqlrc
      bat:  false # ~/.config/bat/config
    }

    # A file in which to store reusable queries
    store: "nupg-query-store.toml"
  }

  try {
    # A table to cache the schemas fetched for autocompletion
    stor create -t nupg_schema_cache -c {
      key: str
      table_name: str
      column_name: str
      pg_type: str
      is_nullable: bool
    }
  } catch {
    print -e "Error when creating the 'nupg_schema_cache' in-memory SQLite table. Maybe it already exists?"
  }
}

# The default set of conversions performed by nupg on query results
#
# You can use this as a base to which to add your own extra conversions
export def default-pg-to-nu-conversions [
]: nothing -> table<pg_type: oneof<string,list<string>>, pg_convert: oneof<closure,nothing>, nu_convert: oneof<closure,nothing>> {
  [
    [pg_type pg_convert nu_convert];

    [boolean null       {$in == "t"}]
    [["text[]" "integer[]" "information_schema.sql_identifier[]"]
      {$"array_to_json\(($in))"}
      {from json}
    ]
    [[json jsonb] null  {from json}]
    [["timestamp without time zone" "timestamp with time zone"]
      null
      {into datetime}]
  ]
}

# The default set of conversions performed by nupg when building queries
# out of nu datatypes
#
# You can use this as a base to which to add your own extra conversions
export def default-nu-to-pg-conversions [
]: nothing -> table<nu_type: oneof<string,list<string>>, pg_type: string> {
  [
    [nu_type  pg_type];

    [string   text]
    [int      integer]
    [float    real]
    [bool     boolean]
    [filesize integer]
    [datetime "timestamp with time zone"]
  ]
}

# Runs 'nupg build ... | nupg run'
export def main [
  ...tokens: string@complete-build
  --args (-a): list<any> = []
] {
  build ...$tokens | run ...$args
}
