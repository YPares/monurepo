export use flake.nu
export use stack.nu

export-env {
  # The nix profile to target by default
  $env.nux.profile-path = $nu.home-dir | path join ".nix-profile"
}

# Just prints the list of 'nux *' subcommands
export def main [] {
  print "Subcommands:"
  for c in (scope commands | where name =~ "^nux ") {
    print $"  - (ansi cyan)($c.name)(ansi reset): ($c.description)"
  }
}
