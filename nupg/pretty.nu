export def format []: string -> string {
  ^sql-formatter -l postgresql
}

export def highlight [--name (-n) = "query"]: string -> string {
  (^bat -l sql --file-name $name
    ...(if $env.nupg.user_configs.bat {[]} else {
      [--no-config --paging=never --theme ansi]
    })
  )
}

# Reformat an SQL query with 'sql-formatter' (nixpkgs#sql-formatter),
# and syntax-highlight it with bat (nixpkgs#bat)
export def main []: string -> string {
  format | highlight 
}

