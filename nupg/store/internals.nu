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

export def complete-stored [] {
  stored-types | insert description {|stored|
    $stored.columns | transpose -rd | $"($in)"
  } | rename -c {name: value}
}
