use std log
use commands.nu *
use atomic.nu

module complete {
  # Used to autocomplete cap name args
  #
  # 'caps' are commits tagged with "<capping:BOOKMARK>". See the 'cap-off'
  # and 'rebase-caps' commands
  export def caps [] {
    get-caps-in-revset | each {{value: $in.bookmark, description: $in.change_id}}
  }
}
export use complete

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
  let revset = $revset | default $env.nujj.caps.revset
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
    # Where to look for caps to rebase. The default is defined by $env.nujj.caps.revset
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

