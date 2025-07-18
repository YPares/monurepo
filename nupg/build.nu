use inspect.nu

export def join-aliases [
  --sep (-s) = ","
  ...args #: list<oneof<string,record>>
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

# TODO: Read this list from a real source of truth
const keywords = [
  select from where
  and or
  join "inner join" "outer join" "cross join" "cross join lateral"
  "group by"
  limit
  distinct
]

export def complete-build [_cmdline _pos] {
  $keywords ++ (inspect schema | each {|tbl|
    [
      {value: $tbl.table_name, description: ""}
      ...($tbl.columns | each {|col|
        {value: $"($tbl.table_name).($col.column_name)"
         description: $"($col.pg_type)(if $col.is_nullable {""} else {' NOT NULL'})"}
      })
    ]
  } | flatten)
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
