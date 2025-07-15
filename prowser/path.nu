def __slice [slice?: range] {
  if $slice != null {
    path split | slice $slice | path join
  } else { $in }
}

export def shorten [
  --keep: number = 5
  --local-root: path
  --color: string
  --highlight
] {
  let path = $in | path expand -n
  let clr_codes = if ($color != null) {{
    root: (
      if $highlight {
        $"(ansi $"($color)_reverse")(ansi attr_italic)(ansi attr_underline)"
      } else {
        $"(ansi $"($color)_italic")(ansi attr_underline)"
      }
    )
    path: (if $highlight {ansi $"($color)_reverse"} else {ansi $color})
    reset: (ansi reset)
  }} else {{}}
  let elems = if $local_root != null {
    $path | path relative-to $local_root | path split
  } else {[]}
  if ($elems | is-empty) {
    let elems = $path | str replace $nu.home-path "~" | path split | slice ((-1 * $keep)..)
    if $local_root != null {
      [
        $"($clr_codes.path?)($elems | slice (..-2) | path join)"
        $"($clr_codes.reset?)($clr_codes.root?)($elems | last)($clr_codes.reset?)"
      ] | path join
    } else {
      $elems | $"($clr_codes.path?)($in | path join)($clr_codes.reset?)"
    }
  } else {
    let keep = [($keep - 1) 1] | math max
    let shortened = if ($elems | length) <= $keep {
      $elems
    } else {
      ["…"] ++ ($elems | slice ((-1 * $keep)..))
    } | path join
    [
      $"($clr_codes.root?)($local_root | path basename)($clr_codes.reset?)($clr_codes.path?)"
      $"($shortened)($clr_codes.reset?)"
    ] | path join
  }
}

export alias slice = __slice
