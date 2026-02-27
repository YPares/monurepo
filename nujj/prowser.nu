use prowser

# Finds the files modified in some revset that match some glob pattern
#
# Used for prowser integration
export def expand-modified-in [revset] {
  let current_arg = $in
  let current_dir = $env.PWD
  let jj_root = ^jj root
  let pattern = if $current_arg != null {
    $current_arg | path expand | path relative-to $jj_root
  } else {""}
  cd $jj_root
  ( ^jj --no-graph
      -r $"\(($revset)) ~ empty\()"
      --template $"self.diff\('glob:($pattern)**/*').files\().map\(|s| s.path\() ++ '(char fs)' ++ committer.timestamp\()).join\('\n') ++ '\n'"
  ) | lines |
    parse $"{path}(char fs){info}" |
    where {$in.path | path exists} |
    update info {into datetime} |
    sort-by info --reverse |
    get path |
    uniq |
    path expand -n |
    each {|path|
      try { $path | path relative-to $current_dir } catch { $path }
    }
}

# Opens prowser with the list of the files modified in the given revset
export def main [revset] {
  prowser browse --multi --prompt $revset {expand-modified-in $revset}
}
