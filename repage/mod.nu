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

# Get the last non-null result
export def ans [] {
  $env.repage.__last_result
}

# Show the input table in less, in full width
export def tless [] {
  $env.config.table.header_on_separator = true
  $env.config.table.footer_inheritance = false
  $in | table -e -w -1 | ^less -SRF --window ((term size).rows / 4 | into int) "-#.25" --header 1
}

def complete-pager [] {
  [less explore fx tw]
}

export def page [pager: string@complete-pager = "less"] {
  match $pager {
    "less" => tless
    "explore" => {explore --index --peek}
    "fx" => {to jsonl | FX_COLLAPSED=1 ^fx}
    "tw" => {to csv | ^tw}
    _ => {error make {msg: $"'($pager)' unknown"}}
  }
}

# Show the last non-null result in full width inside a pager
export def main [pager: string@complete-pager = "less"] {
  if ($env.repage.__last_result | describe) != nothing {
    $env.repage.__last_result | page $pager
  }
}

# Get a compressed summary of the last non-null result
#
# To be used in your prompt
export def render-ans [
  --color (-c) = "yellow"
  --suffix (-s) = ""
] {
  let x = $env.repage.__last_result?
  if ($x | describe) != nothing {
    let width = (term size).columns
  
    let ans_type = $x | describe |
      str replace -r '^(\w{0,3})\w*<' '$1<' |
      str replace -ra ':\s+\b\w+\b' '' |
      str replace -ra '\s' '' | (
        let typ = $in;
        if ($typ | str length -g) >= ($width / 5) {
          $typ | str substring (0..($width / 5 | into int)) | $"($in)…"
        } else {$typ}
      )

    let length = try {
      $"($x | length)L "
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
  ] | insert mode emacs
}

