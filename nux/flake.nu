# Parse nix flake metadata into nu structure
export def metadata [flake: path = "."] {
  ^nix flake metadata $flake --json | from json 
}

# List all the inputs of a flake
export def inputs [flake: path = "."] {
  let md = metadata $flake
  $md.locks.nodes | get $md.locks.root | get inputs
}

# Interactively select which inputs to update
export def update [flake: path = "."] {
  let selected = inputs $flake |
    columns |
    input list --multi "Select flake inputs (<a> for all)"
  if ($selected | is-empty) {
    error make -u "No flake input selected"
  } else {
    ^nix flake update --refresh ...$selected
  }
}
