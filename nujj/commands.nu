use std log
use std formats "from jsonl"
use atomic.nu

module complete {
  def split-and-cleanup-rev-ids [col_name] {
    update $col_name {
      str trim | split row " " | where {is-not-empty} |
      str trim --right --char "*"
    } |
      flatten $col_name
  }

  # Used to autocomplete bookmark args. Lists any bookmark name from the default
  # log revset
  export def local-bookmarks [] {
    (tblog -n
      {value: local_bookmarks
       description: $env.nujj.completion.description
      }
    ) | split-and-cleanup-rev-ids value
  }

  # Used to autocomplete revision args. Lists anything that can be used to
  # identify a revision from the default log revset
  export def revision-ids [] {
    (tblog -n
      {value:
        "change_id.shortest() ++ ' ' ++ commit_id.shortest() ++ ' '
         ++ local_bookmarks ++ ' ' ++ remote_bookmarks ++ ' '
         ++ working_copies"
       description: $env.nujj.completion.description
      }
    ) | split-and-cleanup-rev-ids value
  }

  # Used to autocomplete remote name args
  export def remotes [] {
    ^jj git remote list | lines |
      each {split row " " | {value: $in.0, description: $in.1}}
  }
}
export use complete

module commandline {
  export def describe [--revision (-r): string@"complete revision-ids" = "@"] {
    let msg = ^jj log --no-graph -n1 -T 'description' -r $revision
    let cmd = $"\(^jj describe\n-r ($revision)\n-m '($msg)')"
    commandline edit --replace $cmd
    commandline set-cursor (($cmd | str length) - 2)
  }
}
export use commandline

def to-col-name [] {
  str replace -ra "[()'\":,;|]" "" |
  str replace -ra '[\.\-\+\s]' "_"
}

# Get the jj log as a table
#
# The output table will contain first the columns from anon_templates,
# then those from --named
export def tblog [
  --revset (-r): string@"complete revision-ids"  # Which revisions to log
  --color (-c)  # Keep JJ colors in output values
  --named (-n): record = {}
    # A record of templates, each entry corresponding to a column in the
    # output table
  ...anon_templates: string
    # Anynonymous templates whose names in the output table will be derived
    # from the templates' contents themselves
]: nothing -> table {
  let templates = if (($named | is-empty) and ($anon_templates | is-empty)) {
      $env.nujj.tblog.default | transpose column template
    } else {
      $anon_templates | each {{column: ($in | to-col-name), template: $in}} |
        append ($named | transpose column template)
    }

  (^jj log
    ...(if $revset != null {[-r $revset]} else {[]})
    ...(if $color {[--color always]} else {[]})
    --no-graph
    --template
      $"($templates | get template | str join $"++'(char fs)'++") ++ '(char rs)'"
  ) |
    split row (char rs) |
    each {|row|
      if ($row | str trim | is-not-empty) {
        $row | split row (char fs) |
          zip ($templates | get column) |
          each {{k: $in.1, v: $in.0}} | transpose -rd
      }
    }
}

def list-to-revset [] {
  let list = $in
  if ($list | is-empty) {
    "none()"
  } else {
    $"\(($list | str join '|'))"
  }
}

# Add/remove parent(s) to a rev
export def --wrapped reparent [
  --help (-h)
  --revision (-r): string@"complete revision-ids" = "@" # The rev to rebase
  ...parents: string@"complete revision-ids" # A set of parents each prefixed with '-' or '+'
] {
  let added = $parents | parse "+{rev}" | get rev
  let removed = $parents | parse "-{rev}" | get rev

  ( ^jj rebase -s $revision
       -d $"all:\(($revision)- | ($added | list-to-revset)) & ~($removed | list-to-revset)"
  )
}

# 'kick' is 'jj rebase', but with a twist.
#
# If the revision to rebase is "@", it will be replaced by a new one which we
# will edit (so we remain a the same place in the history), and all bookmarks
# pointing to the previous "@" will be moved to this new one
#
# In any other case it's just a regular 'jj rebase'
export def --wrapped kick [
  --help (-h)
  --revision (-r): string@"complete revision-ids" = "@"
    # A revision to rebase
  --message (-m): string
    # Optionally, change the message of the revision to rebase at the same time
  ...rebase_args # Args to give to jj rebase
] {
  atomic -n kick {
    let revision = if ($revision == "@") {
      ^jj new -A "@"
      ^jj bookmark move --from "@-" --to "@"
      "@-"
    } else {$revision}
    if ($message != null) {
      ^jj desc -m $message -r $revision
    }
    ^jj rebase -r $revision ...$rebase_args
  }
}


# Open a picker to select an operation and restore the working copy back to it
export def back [
  num_ops: number = 15
] {
  clear
  let op = (
    ^jj op log --no-graph -T 'id.short() ++ "\n" ++ description ++ "\n" ++ tags ++ "\n"' -n $num_ops |
    lines | chunks 3 |
    each {|chunk|
      {id: $chunk.0, desc: $"* ($chunk.1) (ansi purple)\n      [($chunk.2)](ansi reset)"}
    } |
    input list -f -d desc
  )
  ^jj op restore $op.id
}

# Split a revision according to one of its past states (identified by a
# commit_id).  Keeps the changes before or at that state in the revision,
# and splits the changes that came after in another rev
export def restore-at [
  restoration_point: string # The past commit to restore the revision at
  --revision (-r): string@"complete revision-ids" = "@" # Which rev to split
  --no-split (-S) # Drop every change that came after restoration_point instead of splitting
] {
  atomic -n restore-at {
    if not $no_split {
      ^jj new --no-edit -A $revision
    }
    ^jj restore --from $restoration_point --to $revision (if not $no_split { --restore-descendants } else {""})
  }
}

# List the bookmarks as a nushell table
export def --wrapped bookmarks [
  ...args: string # Extra args for 'jj bookmark list'
] {
  (
    jj bookmark list
      -T '"{'name:'" ++ json(self.name()) ++ ", 'remote:'" ++ json(self.remote()) ++  ", 'target:'" ++ json(self.normal_target()) ++ "}\n"'
      ...$args
  ) | from jsonl |
    flatten target |
    update author.timestamp {into datetime} |
    update committer.timestamp {into datetime}
}

# Move a bookmark to the next commit
export def advance [
  bookmark: string@"complete local-bookmarks"
] {
  ^jj bookmark move $bookmark --to $"($bookmark)+"
}
