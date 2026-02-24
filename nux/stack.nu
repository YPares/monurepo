# List all packages installed in profile, sorted by priority
export def main [] {
  ^nix profile list --profile $env.nux.profile-path --json | from json |
    get elements |
    transpose name items | flatten items |
    reject active | # Is always true with new flake profiles
    sort-by priority
}

# Add a package to the profile with a higher priority than everything else in it
export def push [flake_ref: path] {
  let prio = match (main) {
    [] => {
      0
    }
    $stk => {
      $stk.0.priority - 10
    }
  }
  ^nix profile add --profile $env.nux.profile-path $flake_ref --priority $prio
}

# Remove the package of the profile with the highest priority
export def pop [] {
  match (main) {
    [] => {
      error make -u "Profile is empty"
    }
    $stk => {
      ^nix profile remove --profile $env.nux.profile-path $stk.0.name
    }
  }
}

# Interactively select which packages to upgrade
export def upgrade [] {
  match (main) {
    [] => {
      error make -u "Profile is empty"
    }
    $stk => {
      let selected = $stk.name | input list --multi
      if ($selected | is-empty) {
        error make -u "No package selected"
      } else {
        ^nix profile upgrade --profile $env.nux.profile-path --refresh ...$selected
      }
    }
  }
}

# Show the packages in the profile with the highest priority
export def render [] {
  let width = (term size).columns
  let pkg_names = main | get name 
  let sep = $"(ansi cyan)|(ansi reset)"
  let num_shown = $width / 20 | into int
  match $pkg_names {
    [] => {
      $"\((ansi grey)empty profile(ansi reset))"
    }
    _ if ($pkg_names | length) <= $num_shown =>  {
      $pkg_names | str join $sep
    }
    _ => {
      let shown_pkgs = $pkg_names | take $num_shown
      let hidden_pkgs = $pkg_names | drop $num_shown
      $shown_pkgs | if $hidden_pkgs != [] {
        append $"+($hidden_pkgs | length)"
      } else { $in } | str join $sep
    }
  }
}
