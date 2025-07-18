# Reformat an SQL query with 'sql-formatter' (nixpkgs#sql-formatter),
# and syntax-highlight it with bat (nixpkgs#bat)
export def main [
  --no-color (-C) # Do not syntax-highlight
  --user-bat-config (-u) # Read user's "~/.config/bat/config" file
]: string -> string {
  ^sql-formatter -l postgresql |
    if $no_color {$in} else {(
      ^bat -l sql
        ...(if $user_bat_config {[]} else {
          [--no-config --paging=never --theme ansi]
        })
    )}
}

