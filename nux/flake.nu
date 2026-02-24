# Parse nix flake metadata into nu structure
export def metadata [--flake (-f): path = "."] {
  ^nix flake metadata $flake --json | from json 
}

# List all the inputs of a flake
export def inputs [--flake (-f): path = "."] {
  let md = metadata --flake=$flake
  $md.locks.nodes | get $md.locks.root | get inputs
}

# Interactively select which inputs to update
export def update [--flake (-f): path = "."] {
  let selected = inputs --flake=$flake |
    columns |
    input list --multi "Select flake inputs (<a> for all)"
  if ($selected | is-empty) {
    error make -u "No flake input selected"
  } else {
    ^nix flake update --flake $flake --refresh ...$selected
  }
}

# List all the outputs of a flake
export def outputs [--flake (-f): path = "."] {
  ^nix flake show --json --quiet --quiet $flake |
    from json |
    transpose output contents |
    where {$in.contents | is-not-empty} |
    transpose -rd
}

# List a flake's output packages for a given system
export def packages [
  --flake (-f): path = "."
  --system: string  # Default is current system
] {
  let system = $system | default {
    ^nix eval --impure --expr builtins.currentSystem --raw
  }
  outputs --flake=$flake | get packages | get $system |
    transpose package contents |
    flatten contents
}
