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
    # will be returned by 'repage ans'
    recorded_types: [stream list record table int float]

    less_args: {||
      [-SRF --window ((term size).rows / 4 | into int) "-#.25"]
    }
  }

  $env.repage.pagers = {
    "less":    {|| table-less}
    "grid":    {|| grid-less}
    "explore": {|| explore --index}
    "fx":      {|| to jsonl | FX_COLLAPSED=1 ^fx}
    "tw":      {|| to csv | ^tw}
  }

  # IMPORTANT: This is not a list of closures, so it will override
  # your own display_output closure if you have any
  $env.config.hooks.display_output = {||
    tee {
      table -a (do $env.repage.max_printed_lines | $in / 2 | into int) | print
    } |
      [($in | describe -d) $in] |
      if ($in.0.type in $env.repage.recorded_types
          or $in.0.detailed_type in $env.repage.recorded_types) {
        $env.repage.__last_result = $in.1
      }
  }
}

# Get the last recorded result
export def ans [] {
  $env.repage.__last_result
}

def --wrapped less-wrapper [...args] {
  ^less ...(do $env.repage.less_args) ...$args
}

# Render the input table in full width, then feed in into less
export def table-less [] {
  $env.config.table.header_on_separator = true
  $env.config.table.footer_inheritance = false
  $in | table -e -w -1 | less-wrapper --header 1
}

# Select a column from the input table, then render it with 'grid',
# then feed it into less
export def grid-less [] {
  print ""
  let v = $in
  let col = match ($v | columns) {
    [$c] => $c
    $cols => {
      try { $cols | input list "Column" }
    }
  }
  if $col != null {
    $v | get $col | grid --color | less-wrapper
  }
}

# List the known pager names
export def complete-pager [] {
  $env.repage.pagers | columns
}

# Execute a pager from $env.repage.pagers on $in
export def in [pager: string@complete-pager = "less"] {
  match ($env.repage.pagers | get -i $pager) {
    null => {
      error make {msg: $"'($pager)' unknown. It is not present in $env.repage.pagers"}
    }
    $cls => {
      do $cls
    }
  }
}

# Show the last recorded result in full width inside a pager
export def main [
  pager: string@complete-pager = "less"
  wrap: oneof<closure, nothing> = null
      # Perform a closure on the stored result before showing it
] {
  let wrap = if $wrap != null {$wrap} else {{$in}}
  if ($env.repage.__last_result? | describe) != nothing {
    $env.repage.__last_result | do $wrap | in $pager
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

export def default-keybindings [--prefix = "repage "] {
  [
    [modifier keycode event];

    [control  char_v  (cmd $'($prefix)less')]
    [control  char_x  (cmd $'($prefix)explore')]
    [control  char_g  (cmd $'($prefix)grid')]
  ] | insert mode emacs
}

