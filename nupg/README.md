# nupg

Make queries to PostgreSQL and get the result as nested Nushell datatypes:

```nushell
> use nupg

> $env.PSQL_DB_STRING = "postgresql://me:me@localhost/mydb"

> nupg select * from some_<Tab>
> nupg select * from some_table
```

## Features

- automatic conversion of Postgres datatypes into the corresponding Nu types (via an env-configurable table of conversions, that can be user expanded) (see `mod.nu`)
- writing queries directly on the command line, with autocompletion (table and table.column names for now) (`nupg` and `nupg build`)
- inlining of Nushell datatypes into queries, so you can e.g. join Nushell tables with PostgreSQL tables (`nupg recordset`)
- feeding values for positional parameters ($1, $2...) and
  named variables (:foo, :'bar'...) from nu datatypes
- pretty printing of produced queries (through bat and sql-formatter) (`nupg pretty`)
- storing queries to reuse them as part as other queries (`nupg store` and its subcommands)

## Dependencies

- `psql` (nixpkgs#postgresql)
- `sql-formatter` (nixpkgs#sql-formatter)
- `bat` (nixpkgs#bat)
