export-env {
  $env.LAST_RESULT = null

  $env.config.hooks.display_output = {||
    tee {table | print} |
    if (($in | describe) != nothing) {
      $env.LAST_RESULT = $in
    }
  }
}

# Get the last non-null result
export def ans [] {
  $env.LAST_RESULT
}

# Show the input table in less, in full width
export def tless [] {
  $env.config.table.header_on_separator = true
  $env.config.table.footer_inheritance = false
  $in | table -e -w -1 | ^less -SRFX --window ((term size).rows / 4 | into int) "-#.25" --header 1
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
  if ($env.LAST_RESULT | describe) != nothing {
    $env.LAST_RESULT | page $pager
  }
}

# Get a compressed summary of the last non-null result
#
# To be used in your prompt
export def render-ans [
  --color (-c) = "yellow_dimmed"
  --suffix (-s) = ""
] {
  if ($env.LAST_RESULT | describe) != nothing {
    let width = (term size).columns
  
    let ans_type = $env.LAST_RESULT | describe |
      str replace -r '^(\w{0,3})\w*<' '$1<' |
      str replace -ra ':\s+\b\w+\b' '' |
      str replace -ra '\s' '' | (
        let typ = $in;
        if ($typ | str length -g) >= ($width / 5) {
          $typ | str substring (0..($width / 5 | into int)) | $"($in)…"
        } else {$typ}
      )

    $"(ansi $color)($ans_type)(ansi reset)($suffix)"
  }
}

