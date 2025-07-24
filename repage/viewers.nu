# A version of 'columns' that returns the types too
export def typed-columns []: any -> table<name: string, type: string> {
  [$in] | flatten | first | # To ensure we always get a record here
    describe -d | get columns | transpose key val |
    each {{name: $in.key, type: $in.val.type}} 
}

def pretty-colname [name] {
  $"(ansi $env.config.color_config.header)($name)(ansi reset)"
}

def pretty-typed-column [] {
  each {$"(pretty-colname $in.name) (ansi attr_italic)\(($in.type))(ansi reset)"}
}

# Run 'less' with the args defined in $env.repage.less_args
export def --wrapped less-wrapper [...args] {
  ^less ...(do $env.repage.less_args) ...$args
}

# Render the input table in full width, then feed in into less
export def table-less [] {
  do --env $env.repage.table_less.override_env
  $in | table -e -w (do $env.repage.table_less.get_max_width) | less-wrapper
}

# Select a column from the input table, then render it with 'grid',
# then feed it into less
export def grid-less [
  --unique (-u) # Remove duplicate values from the column before showing it
  --no-header (-H) # Do not display the column name as a header
] {
  mut to_display = $in
  let col = match (try { $to_display | typed-columns }) {
    null => {
      # This ensures that $to_display is a 1x1 table:
      $to_display = [$to_display] | flatten | wrap values
      "values"
    }
    [$col] => $col.name
    $cols => {try {
      $cols |
        insert text {pretty-typed-column} |
        input list --fuzzy "Column:" -d text |
        get name
    }}
  }
  if $col != null {
    let header = if $no_header {""} else {
      let uniq_bit = if $unique {'unique '} else {""}
      $"(ansi attr_dimmed)-- ($uniq_bit)entries in (ansi reset)(pretty-colname $col)(ansi attr_dimmed):(ansi reset)\n"
    }
    $to_display | get $col |
      if $unique {uniq} else {$in} |
      $header ++ ($in | grid --color) |
      less-wrapper
    print "" # When called from keybinding, if the output of 'grid' is just one line,
             # the new prompt can sometimes by rendered right over the output
             # in some cases
  }
}

# Show the columns from the input table and their types
export def columns-less [] {
  typed-columns | each {pretty-typed-column} |
    wrap columns |
    grid-less -H
}

