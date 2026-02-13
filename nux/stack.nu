# List all packages installed in profile, sorted by priority
export def main [] {
  ^nix profile list --json | from json |
    get elements |
    transpose name items | flatten items |
    reject active | # Is always true with new flake profiles
    sort-by priority
}

# Add a package to the profile with a higher priority than everything else in it
export def push [pkg: path] {
  let prio = match (main) {
    [] => {
      0
    }
    $stk => {
      $stk.0.priority - 10
    }
  }
  ^nix profile add $pkg --priority $prio
}

# Remove the package of the profile with the highest priority
export def pop [] {
  match (main) {
    [] => {
      error make -u "Profile is empty"
    }
    $stk => {
      ^nix profile remove $stk.0.name
    }
  }
}

# Show the N packages in the profile with the highest priority
export def render-stack [--number (-n): int = 5] {
  let pkg_names = main | get name 
  match $pkg_names {
    [] => {
      $"<(ansi grey)empty profile(ansi reset)>"
    }
    _ if ($pkg_names | length) <= $number =>  {
      $"<(ansi cyan)($pkg_names | str join ' ')(ansi reset)>"
    }
    _ => {
      let firstX = ($pkg_names | take $number)
      let others = $pkg_names | drop $number
      $"<(ansi cyan)($firstX | str join ' ')(ansi reset) +($others | length)>"
    }
  }
}
