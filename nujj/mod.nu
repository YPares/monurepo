use std log
use ../nugh

export-env {
  load-env {
    nujj-config: {
      completion: {
        description: "description.first_line() ++ ' (modified ' ++ committer.timestamp().ago() ++ ')'"
      }
      tblog: {
        default: {
          change_id: "change_id.shortest(8)"
          description: description
          author: "author.name()"
          creation_date: "author.timestamp()"
          modification_date: "committer.timestamp()"
        }
      }
      caps: {
        revset: "mutable() & reachable(@, trunk()..)"
      }
    }
  }
}

module complete {
  def split-and-cleanup-rev-ids [col_name] {
    update $col_name {
      str trim | split row " " | where {is-not-empty} |
      str trim --right --char "*"
    } |
      flatten $col_name
  }

  # Used to autocomplete bookmark args Lists any bookmark name from the default
  # log output
  export def local-bookmarks [] {
    (tblog -n
      {value: local_bookmarks
       description: $env.nujj-config.completion.description
      }
    ) | split-and-cleanup-rev-ids value
  }

  # Used to autocomplete revision args Lists anything that can be used to
  # identify a revision from the default log output
  export def revision-ids [] {
    (tblog -n
      {value:
        "change_id.shortest() ++ ' ' ++ commit_id.shortest() ++ ' '
         ++ local_bookmarks ++ ' ' ++ remote_bookmarks ++ ' '
         ++ working_copies"
       description: $env.nujj-config.completion.description
      }
    ) | split-and-cleanup-rev-ids value
  }

  # Used to autocomplete remote name args
  export def remotes [] {
    ^jj git remote list | lines |
      each {split row " " | {value: $in.0, description: $in.1}}
  }

  # Used to autocomplete cap name args
  #
  # 'caps' are commits tagged with "<capping:BOOKMARK>". See the 'cap-off'
  # and 'rebase-caps' commands
  export def caps [] {
    get-caps-in-revset | each {{value: $in.bookmark, description: $in.change_id}}
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
      $env.nujj-config.tblog.default | transpose column template
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

# Run a nushell closure performing a set of jj operations as atomically
# as possible. Ie. if one operation fails, revert back to the state before
# the closure started.
#
# However, this is not a real DB-like transaction, because it is not
# *isolated*: if you run other jj commands in parallel, they can get intertwined
# with those of the closure (and the effect of those parallel operations
# would be cancelled along if the closure fails, which is probably what you
# want anyway in such a case). Note that this should be much improved when
# https://github.com/jj-vcs/jj/pull/4457 lands.
#
# Long story short: don't run several of these in parallel for now, please.
#
# Also, it doesn't make the closure atomic with respect to 'jj undo', which
# will only undo the *last* jj command executed by the closure. This is why
# we print the 'jj op restore' command that you can run later to undo the
# whole closure.
#
# Nesting calls to 'atomic' is allowed. In such a case, the inner calls will
# just be no-ops.
export def atomic [
  --name (-n): string = "anonymous-atomic"
    # A name to show in the nushell logs
  closure: closure
    # A set of jj operations to run atomically
] {
  if ($env.nujj?.atomic-ongoing? == true) {
    log debug $"($name): Already in an atomic block"
    $in | do $closure
  } else {
    let init_op = ^jj op log --no-graph -n1 -T "id.short()" 
    let res = try {
      log debug $"($name): Starting atomic block at op ($init_op)"
      let res = $in | do {
        $env.nujj.atomic-ongoing = true
        $in | do $closure
      }
      let final_op = ^jj op log --no-graph -n1 -T "id.short()" 
      if $final_op == $init_op {
        log debug $"($name): Atomic block finished. Remained at op ($init_op)"
      } else {
        log debug $"($name): Atomic block finished. Now at op ($final_op)"
        log info $"($name): Several jj commands ran. To undo, use '(ansi yellow)jj op restore ($init_op)(ansi reset)'"
      }
      {ok: $res}
    } catch {|exc|
      log error $"($name): Atomic block failed. Reverting to op ($init_op)"
      ^jj op restore $init_op
      {exc: $exc}
    }
    match $res {
      {ok: $x} => { $x }
      {exc: $exc} => { error make $exc.raw }
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

def cap-tag [pattern] {
  $"<capping:($pattern)>"
}

def revs-with-cap-tag [--glob pattern] {
  $"subject\((if $glob {'glob:'} else {''})'(cap-tag $pattern)')"
}

# Find the revisions described by "<capping:BOOKMARK>" in some revset
def get-caps-in-revset [
  --revset (-r): string
]: nothing -> table<colored_change_id: string, change_id: string, bookmark: string> {
  let revset = $revset | default $env.nujj-config.caps.revset
  tblog --color -r $"($revset) & (revs-with-cap-tag --glob "*")" -n {
    colored_change_id: "change_id.shortest(8)"
    subject: "description.first_line()"
  } | insert change_id {get colored_change_id | ansi strip} |
      insert bookmark {get subject | parse (cap-tag "{bm}") | get $.0.bm} |
      reject subject
}

# Rebases the given revision under the given cap. A 'cap' is a revision
# described by <capping:BOOKMARK>
#
# If the revision is @, it will be 'kicked' (see 'kick' command doc)
export def cap-off [
  --revision (-r): string@"complete revision-ids" = "@"
  --message (-m): string # Change the message of the rebased revision at the same time
  --move-bookmark (-b)
    # After rebasing, advance the BOOKMARK to the rebased revision.
    # Does nothing if BOOKMARK is a remote bookmark
  cap: string@"complete caps"
] {
  atomic -n cap-off {
    match (tblog -r (revs-with-cap-tag $cap) change_id) {
      [] => {
        error make {msg: $"No revision is described by (cap-tag $cap)"}
      }
      [{change_id: $change_id}] => {
        kick -r $revision -m $message -B $change_id
        if $move_bookmark and $cap !~ "@" {
          ^jj bookmark set $cap -r $"($change_id)-"
        }
      }
      _ => {
        error make {msg: $"Several revisions are described by (cap-tag $cap)"}
      }
    }
  }
}

# Rebases onto their BOOKMARK all the revisions in a given revset that are described by "<capping:BOOKMARK>"
export def rebase-caps [
  --revset (-r): string@"complete revision-ids"
    # Where to look for caps to rebase. The default is defined by $env.nujj-config.caps.revset
    # By default, we will look for caps in all the mutable revisions outside of trunk() connected in some
    # way to "@"
  --fetch-remote (-f): string@"complete remotes"
    # Before rebasing, run 'jj git fetch' (on the given remote) on the caps'
    # target bookmarks
  --move-bookmarks (-b)
    # After rebasing, advance each BOOKMARK to the revision just below its cap, creating
    # BOOKMARK if it does not exist yet. Does nothing if BOOKMARK is a remote bookmark (ie. contains a '@')
] {
  let caps = get-caps-in-revset -r $revset
  atomic -n rebase-caps {
    if $fetch_remote != null and ($caps | length) > 0 {
      log info $"Fetching ($caps.bookmark | each {[(ansi magenta) $in (ansi reset)] | str join ''} | str join ', ') from ($fetch_remote)"
      ^jj git fetch --remote $fetch_remote ...($caps.bookmark | each {[--branch $in]} | flatten)
    }
    for cap in $caps {
      let bookmark_exists = (tblog -r $"present\(($cap.bookmark))" change_id | length) > 0
      if $bookmark_exists {
        let between = tblog -r $"present\(($cap.bookmark)):: & ($cap.change_id)-" change_id
        if ($between | length) == 0 {
          # $bookmark diverged from $base, we rebase $base:
          log info $"Rebasing ($cap.colored_change_id) onto (ansi magenta)($cap.bookmark)(ansi reset)"
          ^jj rebase -b $cap.change_id -d $cap.bookmark
        }
      }
      if $move_bookmarks and $cap.bookmark !~ "@" {
        log info $"Setting (ansi magenta)($cap.bookmark)(ansi reset) to revision just before ($cap.colored_change_id)"
        ^jj bookmark set $cap.bookmark -r $"($cap.change_id)-"
      }
    }
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

export def mk-gh-revsets [--num-runs = 20] {
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
export def sync-gh-info [
  --num-runs = 20 # We will fetch data about the Nth latest runs (--num-runs <N>)
] {
  let jj_repo_config_path = ^jj root | collect | path join ".jj" "repo" "config.toml"
  let gh_revsets = mk-gh-revsets --num-runs $num_runs
  open $jj_repo_config_path |
    upsert revset-aliases {
      default {} | reject -i ...$nugh.GROUPS | merge $gh_revsets 
    } |
    save -f $jj_repo_config_path
}
