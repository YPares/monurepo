export use stack.nu *

# Just prints the list of 'nux *' subcommands
export def main [] {
  print "Subcommands:"
  for c in (scope commands | where name =~ "^nux ") {
    print $"  - (ansi cyan)($c.name)(ansi reset): ($c.description)"
  }
}
