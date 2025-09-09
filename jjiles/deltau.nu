# delta utils

# Find the system theme (if on Windows/WSL) or leave it to delta to auto-detect
export def theme-flags [] {
  if (which reg.exe | length) > 0 {
    let val = ^reg.exe QUERY 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v SystemUsesLightTheme |
      lines | slice (-2..-2) | split row " " | last
    if $val == "0x1" {
      ["--light"]
    } else {
      ["--dark"]
    }
  } else {
    ["--detect-dark-light" "auto"]
  }
}

# Get the layout flags for delta
export def layout-flags [side_by_side_threshold: int] {
  let width = $env.DELTA_WIDTH? |
    default $env.FZF_PREVIEW_COLUMNS? |
    default $env.FZF_COLUMNS? |
    default (tput cols) |
    into int
  [ --width $width
    ...(if $width >= $side_by_side_threshold {[
        "--side-by-side"
      ]} else {[
        --line-numbers 
        --line-numbers-right-format ""
      ]}
    )
  ]
}

# Run delta with theme and layout detection
export def --wrapped wrapper [--side-by-side-threshold (-s): int = 130, ...args] {
  ^delta ...(theme-flags) ...(layout-flags $side_by_side_threshold) ...$args
}
