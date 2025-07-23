export def get-store []: nothing -> record {
  try { open $env.nupg.store } | default {}
}

export def stored-types [
]: nothing -> table<name: string, columns: table<column_name: string, pg_type: string>> {
  get-store | transpose name vals | flatten vals | select name columns
}

export def stored-queries [
]: nothing -> record {
  [(get-store)] | update cells {get query} | first
}

export def cols-to-desc []: table<column_name: string, pg_type: string> -> string {
  each {|col|
    $"($col.column_name) ($col.pg_type | str upcase)"
  } | str join ", "
}

export def complete-stored [] {
  stored-types | insert description {|stored|
    $stored.columns | cols-to-desc
  } | rename -c {name: value}
}

export def wrap-with-stored [
  --no-stored-queries (-S) # Do not use stored queries
] {
  let query = $in
  if $no_stored_queries {
    $query
  } else {
    let stored_queries = stored-queries
    if ($stored_queries | is-empty) {
      $query
    } else {
      let stored_queries = $stored_queries |    
        transpose key val |
        each {$"($in.key) AS \(($in.val))"} |
        str join ",\n-------------\n"
      $"WITH\n($stored_queries)\n---------------\n($query)"
    }
  }
}
