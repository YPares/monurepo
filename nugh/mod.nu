def mklink [
  text: string
  url: string
] {
  $url | ansi link --text $"(ansi blue)($text)(ansi reset)"
}

def defaults [...vals] {
  let cur = $in
  match $vals {
    [] => $cur
    [$x ..$xs] => {
      $cur | default --empty $x | defaults ...$xs
    }
  }
}

# Get a table of the PRs
export def --wrapped prs [
  --help (-h) # Show this help page
  ...args # Arguments to pass to `gh pr ls`
] {
  ^gh pr ls ...$args --json "number,title,statusCheckRollup,reviewDecision,author,headRefName,headRefOid,baseRefName,url,isDraft" |
  from json | default [] |
  update author {get login} |
  update statusCheckRollup {
    each {|stat|
      let concl = mklink ($stat.conclusion | defaults $stat.status "(unknown)") $stat.detailsUrl
      {workflowName: $stat.workflowName, conclusion: $concl, url: $stat.detailsUrl}
    }
  } |
  update title {|pr|
    let draft = if $pr.isDraft {"Draft: "} else {""}
    mklink $"($draft)($pr.title)" $pr.url
  } |
  rename -c {number: index, headRefName: sourceBranch, headRefOid: sourceCommit, baseRefName: targetBranch, statusCheckRollup: status} |
  move --first index title author sourceBranch targetBranch
}

export const GROUPS = [
  ci_pending ci_success ci_failure
  review_pending review_success review_failure
]

# Group the top commit ids of each prs depending on review status
export def group-pr-commits-by-review [] {
  let pr_list = prs |
    select sourceCommit status reviewDecision |
    insert group {|pr|
      [
        ...(match $pr.reviewDecision {
          "CHANGES_REQUESTED" => ["review_failure"]
          "APPROVED" => ["review_success"]
          "REVIEW_REQUIRED" => ["review_pending"]
          _ => []
        })
      ]
    } |
    flatten group
  match $pr_list {
    [] => {
      {}
    }
    _ => {
      $pr_list |
        group-by group --to-table |
        update items {get sourceCommit} |
        transpose -rd
    }
  }
}

export def runs [--limit (-L) = 20] {
  ^gh run list --json "headSha,status,conclusion" -L $limit | from json | default []
}

export def group-run-commits-by-result [--limit (-L) = 20] {
  let run_list = runs -L $limit | insert group {|run|
    match $run.conclusion {
      "success" => "ci_success"
      "failure" => "ci_failure"
      _ => "ci_pending"
    }
  }
  match $run_list {
    [] => {
      {}
    }
    _ => {
      $run_list |
        group-by group --to-table |
        update items {get headSha} |
        transpose -rd
    }
  }
}
