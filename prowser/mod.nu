# PROmpt broWSER
#
# Open and navigate directories directly from your prompt, and
# browse your files with an extensible fzf-based fuzzy finder
#
# Builds upon nushell's 'std dirs'

use std/dirs
export use path.nu
use rescope *

export-env {
  use std/dirs

  $env.prowser = {
    __prev_dirs_state: null
    __cur_snap_name: null
    __cur_depth_idx: 0
    depth_values: [999,3,2,1]
    excluded: [
      "**/.*/*/**" # Do not recurse into dot directories
    ]
    colors: {
      separator: yellow
      active: light_green
      active_modified: null
      inactive: dark_gray
      depth_indicator: blue
    }
    get_local_root: {|path| null}
    finder: {
      max_height: 40
    }
  }
}

const snaps_file = $nu.default-config-dir | path join "dirs-snapshots.nuon"


export def --env reset [] {
  cd ($env.DIRS_LIST | get $env.DIRS_POSITION)
}

export def --env accept [] {
  $env.DIRS_LIST = $env.DIRS_LIST | update $env.DIRS_POSITION $env.PWD
}

export def --env left [--reset (-r)] {
  if $reset {reset}
  dirs prev
}

export def --env right [--reset (-r)] {
  if $reset {reset}
  dirs next
}

export def --env up [] {
  cd ..
}

def add-left --env [args] {
  match $env.DIRS_POSITION {
    0 => {
      $env.DIRS_LIST = $args ++ $env.DIRS_LIST
    }
    _ => {
      $env.DIRS_LIST = (
        ($env.DIRS_LIST | slice ..($env.DIRS_POSITION - 1)) ++
        $args ++
        ($env.DIRS_LIST | slice $env.DIRS_POSITION..)
      )
    }
  }
  $env.DIRS_POSITION += ($args | length)
  reset
}

def add-right --env [args] {
  $env.DIRS_LIST = (
    ($env.DIRS_LIST | slice ..$env.DIRS_POSITION) ++
    $args ++
    ($env.DIRS_LIST | slice ($env.DIRS_POSITION + 1)..)
  )
}

# Add new dir(s), by default on the right of the current one
export def --env add [
  --left (-l) # Add new dir(s) to the _left_ of the current dir
  ...args # New dirs
] {
  let args = $args | path expand -n
  if $left {
    add-left $args
  } else {
    add-right $args
  }
}

# Drop the current dir
export def --env drop [
  --others (-o) # Drop every dir EXCEPT the current one
] {
  if $others {
    $env.DIRS_LIST = [($env.DIRS_LIST | get $env.DIRS_POSITION)]
    $env.DIRS_POSITION = 0
  } else {
    $env.DIRS_LIST = match $env.DIRS_POSITION {
      0 if ($env.DIRS_LIST | length) == 1 => $env.DIRS_LIST
      0 => ($env.DIRS_LIST | slice 1..)
      $p if $p + 1 == ($env.DIRS_LIST | length) => {
        $env.DIRS_POSITION -= 1
        ($env.DIRS_LIST | slice ..-2)
      }
      _ => (
        ($env.DIRS_LIST | slice ..($env.DIRS_POSITION - 1)) ++
        ($env.DIRS_LIST | slice ($env.DIRS_POSITION + 1)..)
      )
    }
    cd ($env.DIRS_LIST | get $env.DIRS_POSITION)
  }
}

def --env __each [closure: closure] {
  accept
  $env.DIRS_LIST | each {|dir|
    cd $dir
    {index: $dir, out: ($dir | do $closure $dir)}
  }
}

def --env __par-each [closure: closure] {
  accept
  $env.DIRS_LIST | par-each {|dir|
    cd $dir
    {index: $dir, out: ($dir | do $closure $dir)}
  }
}

export def "snap current-state" [] {
  {
    list: $env.DIRS_LIST
    pos: $env.DIRS_POSITION
    depth_idx: $env.prowser.__cur_depth_idx
    name: $env.prowser.__cur_snap_name
  }
}

def "snap saved" [] {
  try { open $snaps_file } catch { {} }
}

export def "snap complete" [] {
  snap saved | transpose value description |
    update description {
      get list | each {path basename} | str join ", "
    }
}

# List all snaps recorded to disk
export def "snap list" [] {
  snap saved | transpose index v | flatten v
}

def --env "snap set" [name snap] {
  $env.prowser.__cur_snap_name = $name
  $env.DIRS_LIST = $snap.list
  $env.DIRS_POSITION = $snap.pos
  $env.prowser.__cur_depth_idx = $snap.depth_idx? | default 0
  reset
}

# Save and load dirs states ("snaps") to/from disk
#
# Will load a snap if called with no flags
export def --env snap [
  name?: string@"snap complete"
    # A name for the snap. Will target the last used snap if not given, or
    # "default" if no snap has been loaded/saved in the current shell 
  --write (-w) # Write a snap (write current dirs state to disk)
  --delete (-d) # Delete a snap from disk
  --previous (-p) # Reset dirs state to the one before last snap was loaded
] {
  let name = $name | default $env.prowser.__cur_snap_name? | default "default"
  if $write {
    accept
    snap saved |
      upsert $name (snap current-state | reject name) |
      save -f $snaps_file
    print $"Saved to snapshot '($name)'"
    $env.prowser.__cur_snap_name = $name
  } else if $delete {
    snap saved | reject $name | save -f $snaps_file
    print $"Deleted snapshot '($name)'"
    if $name == $env.prowser.__cur_snap_name {
      $env.prowser.__cur_snap_name = "default"
    }
  } else if ($previous or $name == "-") {
    accept
    let state_to_restore = $env.prowser.__prev_dirs_state
    $env.prowser.__prev_dirs_state = snap current-state
    if $state_to_restore != null {
      let name_to_restore = $state_to_restore.name?
      snap set $name_to_restore $state_to_restore
      if $name_to_restore != null {
        print $"Back to previous state \(based on snapshot '($name_to_restore)')"
      } else {
        print "Back to previous state"
      }
    } else {
      error make -u {msg: "No previous snapshot known in this shell"}
    }
  } else {
    accept
    let verb = if $name == $env.prowser.__cur_snap_name {"Reloaded"} else {"Loaded"}
    $env.prowser.__prev_dirs_state = snap current-state
    match (snap saved | get -o $name) {
      null => {
        error make -u {msg: $"Snapshot '($name)' unknown"}
      }
      $snap => {
        snap set $name $snap
        print $"($verb) snapshot '($name)'"
      }
    }
  }
}

export def selected-depth [] {
  try {
    $env.prowser.depth_values | get $env.prowser.__cur_depth_idx
  } catch {
    $env.prowser.depth_values.0
  }
}

export def --env switch-depth [] {
  $env.prowser.__cur_depth_idx = ($env.prowser.__cur_depth_idx + 1) mod ($env.prowser.depth_values | length)
}

export def "glob all" [--no-file (-F), --no-dir (-D)] {
  glob $in -l -d (selected-depth) -e $env.prowser.excluded --no-file=$no_file --no-dir=$no_dir
}

export def "glob files" [] {
  glob all -D
}

export def "glob dirs" [] {
  glob all -F
}

def then [cls: closure, --else (-e): any] {
  if $in != null {
    do $cls $in
  } else {$else}
}

export def select-paths [multi: bool, --prompt: string] {
  let dir_clr = $env.config.color_config?.shape_filepath? | default "cyan"
  $in | rescope {
    let color_config_file = mkscoped file { mktemp -t --suffix .nuon }
    $env.config.color_config? | default {} | save -f $color_config_file

    $in | each {|p|
      let type = $p | path expand | path type
      let clr = if $type == "dir" {$dir_clr} else {"default"}
      [ $"(ansi $clr)($p)(ansi reset)(char fs)"
        $type
      ] | str join " "
    } |
    str join "\n" | (
      fzf --reverse --style default --info inline-right
          ...($env.prowser.finder.max_height? | then {[--height $in]} -e [])
          ...($prompt | then {[--prompt $"($in)> "]} -e [])
          --ansi --color "pointer:magenta,marker:green"
          --tiebreak end
          --delimiter (char fs) --with-nth 1 --accept-nth 1
          --cycle --exit-0 --select-1
          --keep-right
          --with-shell 'nu -n --no-std-lib -c'
          --preview $"
            let file = {1}
            let typ = {2}
            $env.config.color_config = open ($color_config_file)
            $env.config.use_ansi_coloring = true
            match $typ {
              "dir" => {
                print $'(ansi ($dir_clr))\($file)(ansi reset):'
                ls --all --short-names $file | table -w \($env.FZF_PREVIEW_COLUMNS | into int)
              }
              _ => {
                bat --color always --terminal-width $env.FZF_PREVIEW_COLUMNS $file
              }
            }
          "
          --preview-window "right,60%,noinfo,border-left"
          --color "scrollbar:blue"
          --bind "ctrl-c:cancel,alt-c:cancel,alt-z:cancel,alt-r:cancel,alt-q:abort"
          --bind "alt-h:first,alt-j:down,alt-k:up,alt-l:accept"
          --bind "alt-left:first,alt-right:accept,alt-up:half-page-up,alt-down:half-page-down"
          --bind "ctrl-alt-k:half-page-up,ctrl-alt-j:half-page-down"
          --bind "alt-backspace:clear-query"
          --bind "ctrl-space:jump"
          --bind "ctrl-a:toggle-all"
          --bind "ctrl-s:half-page-down,ctrl-z:half-page-up"
          --bind "ctrl-d:preview-half-page-down,ctrl-e:preview-half-page-up"
          --bind "ctrl-w:toggle-preview-wrap"
          --bind "resize:execute(tput reset)"
          ...(if $multi {[--multi]} else {[--bind "tab:accept"]})
    ) | lines
  }
}

# Run an fzf-based file fuzzy finder on the paths listed by some closure
#
# If the commandline is empty, it will open the selected files. If not, it will
# act as an auto-completer
#
# Set $env.prowser.excluded to select which patterns should be excluded
export def --env browse [
  glob: closure
  --multi
  --prompt: string
  --ignore-command
  --relative-to: path = "."
] {
  let cmd = if $ignore_command {""} else {
    commandline
  }
  let empty_cmd = $cmd | str trim | is-empty
  let prompt = $"(if $empty_cmd {'open'} else {'complete'})($prompt | then {$"\(($in))"})"
  let elems_before = $cmd |
    str substring 0..(commandline get-cursor) |
    split row -r '\s+'
  let arg = match ($elems_before | reverse) {
    [] => [$env.PWD "**/*"]
    [$x ..$_] => {
      if ($x | path type) == "dir" {
        [$x "**/*"]
      } else {
        [($x | path dirname) $"($x | path basename)*/**"]
      }
    }
  }
  let selected = do {
    cd $arg.0
    let relative_to = $relative_to | path expand -n
    $arg.1 | do $glob | do {
      cd $relative_to
      $in | path relative-to $env.PWD |
        where {is-not-empty} |
        select-paths $multi --prompt $prompt |
        path expand -n
    }
  }
  let selected_types = $selected | each {path expand | path type} | uniq
  match [$empty_cmd $selected $selected_types] {
    [_ [] _] => {}
    [true [$path] [dir]] => {
      cd $path
    }
    [true [$dir ..$rest] [dir]] => {
      cd $dir
      add ...$rest
    }
    [true _ [file]] => {
      commandline edit -r $"($env.EDITOR) ...($selected)" --accept
    }
    _ => {
      commandline edit -r ($elems_before | slice 0..-2 | append $selected | str join " ")
      commandline set-cursor --end
    }
  }
}

export def --env down [] {
  browse --multi --prompt dirs --ignore-command {glob dirs}
}

# To be called in your PROMPT_COMMAND
#
# Shows the opened 'std dirs' and highlights the current one
export def render [] {
  let ds = dirs
  let highlight_active = ($ds | length) > 1
  $ds | each {|d|
    let modified = $d.active and $d.path != ($env.DIRS_LIST | get $env.DIRS_POSITION)
    let color = (
      if $modified {
        $env.prowser.colors.active_modified? | default $env.prowser.colors.active
      } else if $d.active {
        $env.prowser.colors.active
      } else {
        $env.prowser.colors.inactive
      }
    )
    let local_root = if $d.active {
      try { do $env.prowser.get_local_root $d.path }
    }
    let num_elems_to_keep = if $d.active {
      [(5 - ($ds | length)) 2] | math max
    } else {
      1
    }
    $d.path | (
      path shorten
        --keep=$num_elems_to_keep --local-root=$local_root --color=$color
        --highlight=($highlight_active and $d.active)
    ) |
      if $modified and $env.prowser.colors.active_modified == null {
        $"($in)(ansi $color)*(ansi reset)"
      } else {$in}
  } |
    str join $"(ansi $env.prowser.colors.separator)|(ansi reset)" |
    $"(ansi reset)(if $env.prowser.__cur_depth_idx != 0 {$'(ansi $env.prowser.colors.depth_indicator)[↳(selected-depth)](ansi reset)'})($in)"
}

# To be called in your TRANSIENT_ROMPT_COMMAND
export def render-transient [] {
  $env.PWD | path shorten --color=$env.prowser.colors.active --keep (
    if ((term size).columns >= 120) {
      5
    } else {
      3
    }
  )
}

export def sort-by-mod-date [] {
  each {ls -lD $in} | flatten | sort-by -r modified | get name
}

def cmd [cmd] {
  {send: ExecuteHostCommand, cmd: $cmd}
}

# To be added to your $env.config.keybindings in your config.nu
export def default-keybindings [
  --prefix = "prowser "
    # Set this depending on how prowser is imported in your config.nu
] {
  [
    [modifier    keycode        event];

    [control     char_f         (cmd $'($prefix)browse --multi --prompt all {($prefix)glob all}')]
    [alt         char_f         (cmd $'($prefix)browse --multi --prompt by-mod-date {($prefix)glob files | ($prefix)sort-by-mod-date}')]
    [alt         char_r         (cmd $'($prefix)switch-depth')]
    [alt         [left char_h]  (cmd $'($prefix)left')]
    [alt         [right char_l] (cmd $'($prefix)right')]
    [alt         [up char_k]    (cmd $'($prefix)up')]
    [alt         [char_j down]  (cmd $'($prefix)down')]
    [alt         char_s         (cmd $'($prefix)accept')]
    [alt         char_c         (cmd $'($prefix)add $env.PWD; ($prefix)right --reset')]
    [shift_alt   char_c         (cmd $'($prefix)add --left $env.PWD; ($prefix)left --reset')]
    [alt         char_z         (cmd $'($prefix)reset')]
    [alt         char_d         (cmd $'($prefix)drop')]
    [alt         char_q         (cmd $'($prefix)drop --others')]
  ] | insert mode emacs | flatten modifier keycode
}

export alias each = __each
export alias par-each = __par-each
