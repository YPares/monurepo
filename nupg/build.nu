use inspect.nu
use run.nu to-quoted-json
use store/internals.nu *

use ../repage/viewers.nu typed-columns

const keywords_file = (
  path self | path dirname | path join keywords.txt
)

export def join-aliases [
  --sep (-s) = ","
  ...args: oneof<string,record>
]: nothing -> string {
  ($args | each {|arg|
    match ($arg | describe) {
      "string" => {
        [$arg]
      }
      _ => {
        $arg | transpose key val | each {|e|
          $"($e.val) as ($e.key)"
        }
      }
    }
  }) | flatten | str join $sep
}

export def bracket [
  --left (-l): string = "("
  --right (-r): string = ")"
  --sep (-s): string = " "
  ...contents: any
]: [list<any> -> string, nothing -> string] {
  let contents = ($in | default []) ++ $contents
  if ($contents | is-empty) {
    $contents
  } else {
    $"($left)($contents | str join $sep)($right)"
  }
}

def __open [file: path] {
  bracket (open --raw $file)
}

export def select_ [
  ...cols: oneof<string,record>
] {
  $"SELECT (join-aliases ...$cols)"
}

export def from_ [
  ...tables: oneof<string,record>
] {
  $"FROM (join-aliases ...$tables)"
}

export def where_ [
  ...elems: string
] {
  $"WHERE ($elems | str join ' ')"
}

export def complete-build [cmdline pos] {
  mut completions = $keywords_file | open | lines |
    each {{value: $in, style: {fg: yellow}}}

  mut include_columns = false

  let current_word = $cmdline |
    str substring ..<$pos | split row " " | slice (-1).. |
    match $in {
      [""] => ""
      [] => ""
      [$x] => {
        $include_columns = "." in $x
        $x | split row "." | first
      }
    }

  let schema = (
    inspect schema --table-prefix $current_word
  ) ++ (
    stored-types | rename -c {name: table_name}
  )

  for tbl in $schema {
    $completions ++= [{
      value: $tbl.table_name
      style: {fg: magenta}
      description: (
        $tbl.columns | cols-to-desc
      )
    }]

    if $include_columns {
      $completions ++= $tbl.columns | each {|col|
        let null_bit = match $col.is_nullable? {
          false => " NOT NULL"
          _ => ""
        }
        {
          value: $"($tbl.table_name).($col.column_name)"
          style: {fg: blue}
          description: $"($col.pg_type | str upcase)($null_bit)"
        }
      }
    }
  }
  
  {
    options: {
      case_sensitive: false
      completion_algorithm: fuzzy
    }
    completions: $completions
  }
}

# Main function to build an sql query
export def main [
  --bracket-all (-b)
  --sep (-s) = "\n"
  ...args: any@complete-build
]: nothing -> string {
  let left = if $bracket_all {"("} else {""}
  let right = if $bracket_all {")"} else {""}
  $args | bracket --left $left --right $right --sep $sep
}

# Use the contents of a nu table into a query. Each row of the nu table
# will be treated as a separated row (record) in PostgreSQL
# 
# The final table will be ($in ++ $table)
#
# Will use the mappings defined in $env.nupg.conversions.nu_to_pg
export def recordset [
  --name (-n) = "record" # How to name each record (row) in the query
  --parameter (-p): int
    # Do not splice in the table, instead insert its inferred type
    # along with a $n positional placeholder
  --variable (-v): string
    # Do not splice in the table, instead insert its inferred type
    # along with a :'name' named placeholder
  table: table = []
]: [nothing -> string, table -> string] {
  let table = ($in | default []) ++ $table
  if ($table | is-empty) {
    error make -u {msg: "recordset: Table is empty"}
  }

  let types = $table | typed-columns |
    join --left ($env.nupg.conversions.nu_to_pg) type nu_type 

  let pg_cols = $types |
    each {
      $"\"($in.name)\" ($in.pg_type? | default "jsonb")"
    } |
    str join ","

  let contents = match [$parameter $variable] {
    [$p $_] if $p != null => {
      $"$($p)"
    }
    [$_ $v] if $v != null => {
      $":'($v)'"
    }
    _ => {
      $table | to-quoted-json
    }
  }
  $"jsonb_to_recordset\(($contents)) as ($name)\(($pg_cols))"
}

export alias open = __open
