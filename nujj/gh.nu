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
  jj log -r (
    "trunk()..(" ++
    (
      gh pr list -S $"review-requested:($githubHandle)" --json headRefOid |
        from json | get headRefOid | str join '|'
    ) ++
    ")"
  )
}
