use ../nugh

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
  let jj_repo_config_path = ^jj root | collect | path join ".jj" "repo" "config.toml"
  let gh_revsets = mk-revsets --num-runs $num_runs
  open $jj_repo_config_path |
    upsert revset-aliases {
      default {} | reject -i ...$nugh.GROUPS | merge $gh_revsets 
    } |
    save -f $jj_repo_config_path
}
