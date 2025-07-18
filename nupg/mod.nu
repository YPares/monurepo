export use run.nu *
export use build.nu *
export use inspect.nu

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

    [boolean null       {$in == "t"}]
    [["text[]" "integer[]" "information_schema.sql_identifier[]"]
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

# Reformat an SQL query with 'sql-formatter' (nixpkgs#sql-formatter),
# and syntax-highlight it with bat (nixpkgs#bat)
export def pretty [
  --no-color (-C) # Do not syntax-highlight
  --user-bat-config (-u) # Read user's "~/.config/bat/config" file
]: string -> string {
  ^sql-formatter -l postgresql |
    if $no_color {$in} else {(
      ^bat -l sql
        ...(if $user_bat_config {[]} else {
          [--no-config --paging=never --theme ansi]
        })
    )}
}
