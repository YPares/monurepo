def __slice [slice?: range] {
  if $slice != null {
    path split | slice $slice | path join
  } else { $in }
}

export def shorten [
  --keep: number
  --local-root: path
  --color: string
  --highlight
] {
  let path = $in | path expand -n
  let slice = if $keep == null {(0..)} else {((-1 * $keep)..)}
  let clr_codes = if ($color != null) {{
    root: (ansi $"($color)_underline")
    path: (if $highlight {ansi $"($color)_reverse"} else {ansi $color})
    reset: (ansi reset)
  }} else {{}}
  if $local_root == null {
    $path | str replace $env.HOME "~" | __slice $slice | $"($clr_codes.path?)($in)"
  } else {
    let elems = $path | path relative-to $local_root | path split
    let local_root = $"($clr_codes.root?)($local_root | path basename)($clr_codes.reset?)($clr_codes.path?)"
    let elems = if ($elems | is-empty) {
      [$local_root "."]
    } else if ($elems | length) <= $keep {
      [$local_root ...$elems]
    } else {
      [$local_root "…" ...($elems | slice $slice)]
    }
    $elems | path join
  } | $"($in)($clr_codes.reset?)"
}

export alias slice = __slice
