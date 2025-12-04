use prowser

# Finds the files modified in some revset that match some glob pattern
#
# Used for prowser integration
export def glob-modified-in [revset] {
  let pattern = $in | default "**/*"
  let pattern = $env.PWD | path join $pattern
  cd (^jj root)
  ( ^jj --no-graph
      -r $"\(($revset)) ~ empty\()"
      --template $"self.diff\('glob:($pattern)').files\().map\(|s| s.path\() ++ '(char fs)' ++ committer.timestamp\()).join\('\n') ++ '\n'"
  ) | lines |
    parse $"{path}(char fs){info}" |
    where {$in.path | path exists} |
    update info {into datetime} |
    sort-by info --reverse |
    get path | uniq | path expand -n
}

# Opens prowser with the list of the files modified in the given revset
export def main [revset] {
  prowser browse --multi --prompt $revset {glob-modified-in $revset}
}
