export-env {
  $env.repage = {
    __last_result: null

    # How many lines should non-paginated displayed results take at most
    #
    # By default it is made so any output always fits on one page
    #
    # It will be rounded down so this can return a float
    max_printed_lines: {|| (term size).rows * 3 / 4}

    # The types that repage should record as the last result, which
    # will then be returned by 'repage ans'.
    # Types not in this list will not be recorded, and thus the last
    # result will hold its value.
    # This is to "fiter out" irrelevant data that you might not want
    # to erase your last result with.
    #
    # Setting this to null will force every result to be recorded,
    # whatever its type, EXCEPT null values
    recorded_types: [stream list record table]

    # Arguments to be given to 'less'
    # It is a closure so that we can query dynamic values (such as
    # terminal width) every time it is needed
    less_args: {||
      [-SRF --window ((term size).rows / 4 | into int) "-#.25"]
    }

    # A record of closures that render on stdout a value that is piped in
    #
    # You can add your own functions to it:
    # $env.repage.viewers = $env.repage.viewers | merge {...}
    viewers: {
      "less":      {|| table-less}
      "grid-all":  {|| grid-less}
      "grid-uniq": {|| grid-less --unique}
      "explore":   {|| explore --index}
      "fx":        {|| to jsonl | FX_COLLAPSED=1 ^fx}
      "tw":        {|| to csv | ^tw}
    }
  }
}

# Record the value fed via pipeline input, if this value fits some conditions,
# and then render it with 'table'.
#
# To be used as your $env.config.hooks.display_output
export def --env record-and-render []: any -> string {
  tee {
    table -a (do $env.repage.max_printed_lines | $in / 2 | into int) | print
  } |
    [($in | describe -d) $in] |
    if $in.0.type != "nothing" and (
      $env.repage.recorded_types? == null
      or $in.0.type in $env.repage.recorded_types
      or $in.0.detailed_type in $env.repage.recorded_types
    ) {
      $env.repage.__last_result = $in.1
    }
}

# Get the last recorded result
export def ans [] {
  $env.repage.__last_result
}

export def --wrapped less-wrapper [...args] {
  ^less ...(do $env.repage.less_args) ...$args
}

# Render the input table in full width, then feed in into less
export def table-less [] {
  $env.config.table.header_on_separator = true
  $env.config.table.footer_inheritance = false
  $in | table -e -w -1 | less-wrapper --header 1
    # Using --header implies that the output of less will always be
    # at least one screen long, with extra ~'s at the beginning of
    # extra lines if the input isn't long enough. 
    # 
    # TODO: find a way to avoid that
}

# Select a column from the input table, then render it with 'grid',
# then feed it into less
export def grid-less [
  --unique (-u) # Remove duplicate values from the column before showing it
] {
  let v = $in
  let col = match ($v | columns) {
    [$c] => $c
    $cols => {
      try { $cols | input list --fuzzy "Column" }
    }
  }
  if $col != null {
    $v | get $col |
      if $unique {uniq} else {$in} |
      grid --color |
      less-wrapper
  }
  print "" # When called from keybinding, if the output of 'grid' is just one line,
           # the new prompt can sometimes by rendered right over the output
           # in some cases
}

# List the known viewer names
export def viewers [] {
  $env.repage.viewers | columns
}

# Execute a viewer from $env.repage.viewers on $in
export def in [
  --viewer (-v): string@viewers = "less"
] {
  match ($env.repage.viewers | get -i $viewer) {
    null => {
      error make {msg: $"'($viewer)' unknown. It is not present in $env.repage.viewers"}
    }
    $cls => {
      do $cls
    }
  }
}

# Show the last recorded result in full width inside a viewer
export def main [
  --select (-s) # Open a dropdown list to select the viewer (ignore -v then)
  --viewer (-v): string@viewers = "less"
  wrap: oneof<closure, nothing> = null
      # Perform a closure on the stored result before showing it
] {
  let wrap = if $wrap != null {$wrap} else {{$in}}
  let viewer = if $select {
    try { viewers | input list --fuzzy "Viewers" }
  } else {$viewer}
  if $viewer != null and ($env.repage.__last_result? | describe) != nothing {
    $env.repage.__last_result | do $wrap | in -v $viewer
  }
}

# Get a compressed summary of the last recorded result,
# or an empty string if no result is recorded
#
# To be used in your prompt
export def render-ans-summary [
  --color (-c) = "yellow" # Which color to render the type in
  --truncate # Truncate the summary depending on terminal width
  --suffix (-s) = "" # If an output is produced, add this suffix to it
] {
  let ans = $env.repage.__last_result?
  if ($ans | describe) != nothing {
    let width = (term size).columns
  
    let ans_type = $ans | describe |
      str replace -r '^(\w)\w*<' '$1<' |
      str replace -ra ':\s+\b\w+\b' '' |
      str replace -ra '\s' '' | (
        let typ = $in;
        if $truncate and (($typ | str length -g) >= ($width / 5)) {
          $typ | str substring (0..($width / 5 | into int)) | $"($in)…"
        } else {$typ}
      )

    let length = try {
      $"($ans | length)L "
    } catch {""}

    $"($length)(ansi reset)(ansi $color)($ans_type)(ansi reset)($suffix)"
  }
}

def cmd [cmd] {
  {send: ExecuteHostCommand, cmd: $cmd}
}

# Keybindings to be used as an example
#
# You can use them straightaway or set your own in your config.nu
export def default-keybindings [] {
  [
    [modifier keycode event];

    [control     char_v (cmd $'print ""; repage -s')]
    [control_alt char_v (cmd $'repage -v less')]
    [control     char_x (cmd $'repage -v explore')]
    [control_alt char_x (cmd $'print ""; repage -v grid-uniq')]
  ] | insert mode emacs
}

