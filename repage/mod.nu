use viewers.nu

export-env {
  $env.repage = {
    __recorded: null

    # How to show (summarized) results of commands
    #
    # Will be used in 'record-and-render'
    display_output: {||
      table -a ((term size).rows * 3 / 4 | $in / 2 | into int) | print
    }

    # The types that repage should record as the last result, which
    # will then be returned by 'repage ans'.
    # Types not in this list will not be recorded, and thus the last
    # result will hold its value.
    # This is to "fiter out" irrelevant data that you might not want
    # to erase your last result with.
    #
    # Setting this to null will force every result to be recorded,
    # whatever its type, EXCEPT null values
    recorded_types: [list record table]

    # Arguments to be given to 'less'
    # It is a closure so that we can query dynamic values (such as
    # terminal width) every time it is needed
    less_args: {||
      [-SRF --window ((term size).rows / 4 | into int) "-#.25"]
        # Add '--header 1' if you want to keep the first line as a
        # sticky header.
        # 
        # However, using --header implies that the output of less will always be
        # at least one screen long, with extra ~'s at the beginning of
        # extra lines if the input isn't long enough. 
        # 
        # TODO: find a way to avoid that
    }

    # Override your env specifically for the case of 'table-less',
    # notably Nu formatting settings.
    # 
    # You can use this to display some datatypes in more detail in the
    # pager context
    table_less_override_env: {||
      ## These make sense if --header 1 is used in 'less_args':
      # $env.config.table.header_on_separator = true
      # $env.config.table.footer_inheritance = false

      # $env.config.table.padding = {left: 0, right: 0}
      $env.config.datetime_format.table = "%c"
      $env.config.filesize.precision = 3
    }

    # A record of closures that render on stdout a value that is piped in
    #
    # You can add your own functions to it:
    # $env.repage.viewers = repage default-viewers | merge {...}
    viewers: (default-viewers)
  }
}

# Record the value fed via pipeline input, if this value fits some conditions,
# and then render it with 'table'.
#
# To be used as your $env.config.hooks.display_output
export def --env record-and-render [
  --force (-f) # Force recording, even if the type doesn't match $env.repage.recorded_types
]: any -> string {
  record --force=$force | do $env.repage.display_output 
}

# Record the value fed via pipeline input, if this value fits some conditions,
# and return it
export def --env record [
  --force (-f) # Force recording, even if the type doesn't match $env.repage.recorded_types
] {
  [
    ($in | describe -d)
    $in
  ] | if $force or $in.0.type != "nothing" and (
    $env.repage.recorded_types? == null
    or $in.0.type in $env.repage.recorded_types
    or (try { $in.0.subtype?.type in $env.repage.recorded_types }) == true
      # .subtype may exist but not be a record.
      # .subtype record exists for streams, and gives the type of the data
      # when the stream is resolved
  ) {
    $env.repage.__recorded = $in.1
    $in.1
  } else {
    $in.1
  }
}

# Get the last recorded result
export def ans [] {
  $env.repage.__recorded
}

# Erase the last recorded result
#
# Equivalent to 'null | repage record -f'
export def --env drop [] {
  $env.repage.__recorded = null
}

def list-viewers [] {
  $env.repage.viewers | columns
}

# Execute a viewer from $env.repage.viewers on $in
export def in [
  --viewer (-v): string@list-viewers = "less"
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

def complete-ans-columns [] {
  ans | viewers typed-columns | rename value description
}

# Show the last recorded result in full width inside a viewer
export def main [
  --select (-s) # Open a dropdown list to select the viewer (ignore -v then)
  --viewer (-v): string@list-viewers = "less"
                # Which viewer (from $env.repage.viewers) to use
  --wrap (-w): oneof<closure, nothing> = null
      # Process the recorded result (post column filtering) before showing it
  ...columns: string@complete-ans-columns # The columns of the recorded result to select.
                                 # Selects all the columns if none given
] {
  let wrap = if $wrap != null {$wrap} else {{$in}}
  let viewer = if $select {
    try { list-viewers | input list --fuzzy "Viewer:" }
  } else {$viewer}
  if $viewer != null and ($env.repage.__recorded? | describe) != nothing {
    $env.repage.__recorded |
      if ($columns | is-empty) {$in} else {select ...$columns} |
      do $wrap |
      in -v $viewer
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
  let ans = $env.repage.__recorded?
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

# The default set of viewers used by repage when you import this module
export def default-viewers []: nothing -> record {{
  "columns":   {|| viewers columns-less}
  "less":      {|| viewers table-less}
  "grid-all":  {|| viewers grid-less}
  "grid-uniq": {|| viewers grid-less --unique}
  "explore":   {|| explore --index}
  "fx":        {|| to jsonl | FX_COLLAPSED=1 ^fx}
  "tw":        {|| to csv | ^tw}
}}

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
    [control     char_w (cmd $'repage -v less')]
    [control     char_x (cmd $'repage -v explore')]
    [control_alt char_x (cmd $'print ""; repage -v grid-uniq')]
    [control_alt char_c (cmd $'print ""; repage -v columns')]
  ] | insert mode emacs
}

