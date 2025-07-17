export use atomic.nu
export use commands.nu *
export use caps.nu *
export use gh.nu

export-env {
  load-env {
    nujj: {
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

export def default-keybindings [--prefix = "nujj "] {
  [
    [modifier    keycode        event];

    [control_alt char_n  (cmd $'($prefix)commandline describe')]
  ] | insert mode emacs
}
