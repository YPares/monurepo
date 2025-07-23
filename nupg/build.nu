use inspect.nu
use store/internals.nu *

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
  ...contents: string
]: [list<string> -> string, nothing -> string] {
  let contents = ($in | default []) ++ $contents
  let contents = $contents | str trim | where {is-not-empty}
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
  mut values = $keywords_file | open | lines |
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

  let schema = inspect schema --table-prefix $current_word

  for tbl in $schema {
    $values ++= [{
      value: $tbl.table_name
      style: {fg: magenta}
      description: (
        $tbl.columns | cols-to-desc
      )
    }]

    if $include_columns {
      $values ++= $tbl.columns | each {|col| {
        value: $"($tbl.table_name).($col.column_name)"
        style: {fg: blue}
        description: $"($col.pg_type | str upcase)(if $col.is_nullable {""} else {' NOT NULL'})"
      }}
    }
  }
  
  {
    options: {
      case_sensitive: false
      completion_algorithm: fuzzy
    }
    completions: ($values ++ (complete-stored))
  }
}

# Main function to build an sql query
export def main [
  --bracket-all (-b)
  --sep (-s) = "\n"
  ...args: string@complete-build
] {
  let left = if $bracket_all {"("} else {""}
  let right = if $bracket_all {")"} else {""}
  $args | bracket --left $left --right $right --sep $sep
}

export alias open = __open
