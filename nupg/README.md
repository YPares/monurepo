# nupg

Make queries to PostgreSQL and get the result as nested Nushell datatypes.

## Features

- automatic conversion of Postgres datatypes into the corresponding Nu types (via an env-configurable table of conversions, that can be user expanded)
- writing queries directly on the command line, with some limited autocompletion (table and table.column names for now)
- some simple higher-level query builders (to build query parts out of regular Nu records)
- pretty printing of the produced queries (through bat and sql-formatter)
- storing queries to reuse them as part as other queries (_experimental_)

## Dependencies

- `psql` (nixpkgs#postgresql)
- `sql-formatter` (nixpkgs#sql-formatter)
- `bat` (nixpkgs#bat)
