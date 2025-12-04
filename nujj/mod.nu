export use atomic.nu
export use commands.nu *
export use caps.nu *
export use prowser.nu
export use gh.nu

export-env {
  $env.nujj = {
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

def cmd [cmd] {
  {send: ExecuteHostCommand, cmd: $cmd}
}

export def default-keybindings [--prefix = "nujj "] {
  [
    [modifier    keycode event];

    [control_alt char_n  (cmd $'($prefix)commandline describe')]
    [alt char_f          (cmd $"($prefix)prowser 'ancestors\(@,2)'")]
    [control_alt char_f  (cmd $"($prefix)prowser 'reachable\(@,mutable\())'")]
  ] | insert mode emacs
}
