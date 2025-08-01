use prowser

# Finds the files modified in some revset that match some glob pattern
#
# Used for prowser integration
export def glob-recent [] {
  let pattern = $in | default "**/*"
  let pattern = $env.PWD | path join $pattern
  cd (^jj root)
  ( ^jj --no-graph
      -r $"\(($env.nujj.recent_files_revset)) ~ empty\()"
      --template $"self.diff\('glob:($pattern)').files\().map\(|s| s.path\() ++ '(char fs)' ++ committer.timestamp\()).join\('\n') ++ '\n'"
  ) | lines |
    parse $"{path}(char fs){info}" |
    where {$in.path | path exists} |
    update info {into datetime} |
    sort-by info --reverse |
    get path | uniq | path expand -n
}

# Opens prowser with the list of the files modified in recent JJ revisions
export def browse-recent [] {
  prowser browse --multi --prompt jj-recent {glob-recent}
}
