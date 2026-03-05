use nugh

export def mk-revsets [--num-runs = 20] {
  let list = nugh group-run-commits-by-result -L $num_runs |
    merge (nugh group-pr-commits-by-review) |
    transpose group commit_ids |
    update commit_ids {
      each {$"present\(($in))"} | str join "|"
    }
  match $list {
    [] => {{}}
    _ => {
      $list | transpose -rd
    }
  }
}

# Stores in the repo's config information from the github repo
#
# Currently, this stores into revsets info related to CI runs and PR reviews
export def sync-info [
  --num-runs = 20 # We will fetch data about the Nth latest runs (--num-runs <N>)
] {
  let jj_repo_config_path = ^jj config path --repo
  let gh_revsets = mk-revsets --num-runs $num_runs
  open $jj_repo_config_path |
    upsert revset-aliases {
      default {} | reject -o ...$nugh.GROUPS | merge $gh_revsets 
    } |
    save -f $jj_repo_config_path
}

# Show the jj log of all commits to be reviewed by the given GitHub user
export def with-reviewer [githubHandle: string] {
  let heads = (
    gh pr list -S $"review-requested:($githubHandle)" --json headRefOid |
    from json | get headRefOid
  )
  match $heads {
    [] => {}
    _ => {
      jj log -r $"trunk\()..\(($heads | each {$"present\(($in))"} | str join '|'))"
    }
  }
}

# Check the runs associated with a revision
export def --wrapped ci [
  --revision (-r) = "@" # Which revision search runs for
  ...args # Args for `gh run view` 
] {
  let runs = (
    gh run list -c (jj -r $revision -T commit_id) --json databaseId,createdAt
  ) |
    from json |
    update createdAt {into datetime} |
    sort-by datetime -r
  for run in $runs {
    print $"(ansi yellow)# Run ($run.databaseId), created at ($run.createdAt)(ansi reset)"
    gh run view $run.databaseId ...$args
  }
}

# Submit a revision as a PR. Base is autodetected
export def --wrapped submit [
  --head (-H) = "@-" # Which revision to use as PR head
  ...args # Args for `gh pr create`
] {
  let head_bms = jj -r $head -GT local_bookmarks | split row " "
  let base_bms =  jj -r $"heads\(::($head)- & remote_bookmarks\())" -GT local_bookmarks | split row " "
  match $head_bms {
    [_] => {}
    _ => {
      error make -u $"($head) should have exactly one bookmark"
    }
  }
  match $base_bms {
    [_] => {}
    _ => {
      error make -u $"Branch to use as base is ambiguous: found ($base_bms)"
    }
  }
  gh pr create -H $head_bms.0 -B $base_bms.0 ...$args
}
