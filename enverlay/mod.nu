export-env {
  $env.enverlay.autoload_direnv = null
  $env.enverlay.excluded_direnv_vars = [name NAME LANG LOCALE_ARCHIVE]
    # This are set by nix-based .envrc files, and you most likely don't want to change the ones you have already

  $env.config.hooks.env_change.PWD = $env.config.hooks.env_change.PWD? | default [] | append {||
    match $env.enverlay.autoload_direnv? {
      # Auto load & unload:
      "full" => { load }
      # Only load if a .envrc is found. Else keep the env:
      "load" if (".envrc" | path exists) => { load }
    }
  }
}

export def allow [dir: path = "."] {
  cd $dir
  ^direnv allow
}

export def revoke [dir: path = "."] {
  cd $dir
  ^direnv revoke
}

def __export [dir: path = "."] {
  cd $dir
  let proc = ^direnv export json | complete
  let e = if (
       ($proc.stderr | is-empty)
    or ($proc.stderr | lines | last | ansi strip) =~ "^direnv: (export|unloading)"
  ) {
    $proc.stdout | from json | default {} | reject -o ...$env.enverlay.excluded_direnv_vars
  } else {
    error make {msg: $"direnv errored:\n($proc.stderr)"}
  }
  if ($e has PATH) {
    $e | update PATH {split row (char env_sep)}
  } else {$e}
}

export def status [] {
  ^direnv status --json | from json
}

# Tries to find a .envrc in the given directory, and loads it.
# The directory should be allowed with `direnv allow` first.
#
# If the directory doesn't contain a .envrc, unloads the current env
export def --env load [dir: path = "."] {
  let jid = job spawn {
    sleep 0.1sec
    print -n $"(ansi grey)direnv loading...(ansi default)"
  }
  load-env (__export $dir)
  try { job kill $jid }
  let loadedRC = status | get state.loadedRC?
  if $loadedRC != null and $loadedRC.allowed? != 0 {
    error make {msg: $"($loadedRC.path) is not allowed"}
  }
}

export def dir [] {
  if $env.DIRENV_FILE? != null {
    $env.DIRENV_FILE | path dirname
  }
}

export def --env auto [--load-only (-l)] {
  $env.enverlay.autoload_direnv = if $load_only {
    "load"
  } else if $env.enverlay.autoload_direnv? == null {
    "full"
  }
}

export def render [] {
  let width = (term size).columns

  let envs = [
    ...(
      match ($env | get -o name) { # Nix shell/develop set the $name (lowercase) env var
        null => []
        $name => [$"(ansi blue)❄ ($name)(ansi reset)"]
      }
    )
    ...(
      match (dir) {
        null => []
        $path => [$"(ansi yellow)📂($path | path basename)(ansi reset)"]
      }
    )
  ]
  let direnv_auto_bit = if $env.enverlay.autoload_direnv? != null {
    $"(ansi magenta)📂auto\(($env.enverlay.autoload_direnv))(ansi reset) "
  }
  let envs_bit = $envs | each {[$in ' ']} | flatten | str join ""
  let num_shown_overlays = $width / 35 | into int
  let overlays = overlay list | match ($in | describe) {
    # Pre-Nu 0.107: 'active' column doesn't exist:
    "list<string>" => {$in | wrap name | insert active true}
    _ => $in
  } | reverse
  let overlays_bit = $overlays |
    take $num_shown_overlays |
    each {|o|
      if $o.active {
        $o.name
      } else {
        $"(ansi grey)(ansi attr_strike)($o.name)(ansi reset)"
      }
    } |
    str join $"(ansi yellow)|(ansi reset)" | if ($overlays | length) > $num_shown_overlays {
      $"($in)(ansi yellow)|(ansi reset)…"
    } else {$in}

  $"($direnv_auto_bit)($envs_bit)($overlays_bit)"
}

def cmd [cmd] {
  {send: ExecuteHostCommand, cmd: $cmd}
}

export def default-keybindings [--prefix = "enverlay "] {
  [
    [modifier keycode event];

    [alt      char_e  (cmd $'overlay new direnv; ($prefix)load')]
  ] | insert mode emacs
}

export alias export = __export
