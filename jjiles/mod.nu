use nujj
use deltau.nu
use parsing.nu

const jjiles_dir = path self | path dirname

const fzf_callbacks = $jjiles_dir | path join fzf-callbacks.nu

const default_config_file = $jjiles_dir | path join default-config.toml


def --wrapped cond [bool ...flags] {
  if $bool {$flags} else {[]}
}

def --wrapped cmd [
  --fzf-command (-c): string = "reload"
  ...args: string
]: nothing -> string {
  $"($fzf_command)\(nu -n ($fzf_callbacks) ($args | str join ' '))"
}

def used-keys []: record -> table<key: string> {
  columns | each { split row "," } | flatten | each {str trim} | wrap key
}

def to-fzf-bindings []: record -> list<string> {
  transpose keys actions | each {|row|
    [--bind $"($row.keys):($row.actions | str join "+")"]
  } | flatten
}

def to-fzf-colors [mappings: record, theme: string]: record -> string {
  transpose elem color | each {|row|
    let map = $mappings | get -o $row.color 
    let color = if ($map != null) {
      $map | get -o $theme | default $map.default?
    } else {
      $row.color | str join ":"
    }
    if ($color != null) {
      $"($row.elem):($color)"
    }
  } | str join ","
}

# Runs a list of finalizers and optionally (re)throws an exception
def finalize [finalizers: list<closure>, exc?] {
  for closure in $finalizers {
    do $closure
  }
  if ($exc != null) {
    let exc = if (($exc | describe) == "string") {{msg: $exc}} else {$exc}
    std log error $exc.msg
    error make $exc
  }
}

# (char us) will be treated as the fzf field delimiter.
# 
# Each "line" of the oplog/revlog will therefore be seen by fzf as:
# `jj graph characters | change_or_op_id | commit_id? | user template (char gs)`
# with '|' representing (char us)
# Fzf can then only show fields 1 & 4 to the user (--with-nth) and we can reliably
# extract the data we need from the other fields
# 
# We terminate the template by (char gs) because JJ cannot deal with templates containing NULL
def wrap-template [...args] {
  $args |
    each {[$"'(char us)'" $in]} |
    flatten |
    append [$"'(char gs)'"] | 
    str join "++"
}

# Get the bits of JJ's config that jjiles need to work
def get-needed-config-from-jj [
  jj_config: record
] {
  let process = {
    let clr = $in
    let clr = match ($clr | describe) {
      "string" => $clr
      _ => $clr.fg
    }
    match ($clr | parse "bright {color}") {
      [{color: $c}] => $"light_($c)"
      _ => $clr
    }
  }
  {
    revsets: {
      log: $jj_config.revsets.log
    }
    templates: {
      op_log: $jj_config.templates.op_log
      log: $jj_config.templates.log
    }
    colors: {
      operation: ($jj_config.colors."operation id" | do $process)
      revision: ($jj_config.colors.change_id | do $process)
      commit: ($jj_config.colors.commit_id | do $process)
    }
  }
}

def get-templates [jj_cfg jjiles_cfg] {
  {
    op_log: ($jjiles_cfg.templates.op_log? | default $jj_cfg.templates.op_log)
    rev_log: ($jjiles_cfg.templates.rev_log? | default $jj_cfg.templates.log)
    evo_log: ($jjiles_cfg.templates.evo_log? | default $jj_cfg.templates.log)
    rev_preview: $jjiles_cfg.templates.rev_preview?
    evo_preview: $jjiles_cfg.templates.evo_preview
    file_preview: $jjiles_cfg.templates.file_preview?
  }
}

export def git-ignored [repo_root_abs]: nothing -> list<string> {
  glob $"($repo_root_abs)/**/.gitignore" | each {|f|
    open $f | lines | str trim | where {$in != ""} | each {|pat|
      let pat = if ($pat | str starts-with "/") {
        $".($pat)" # paths beginning with '/' trip the 'path join' command
      } else {$pat}
      $f | path dirname | path join $pat |
        path expand -n | path relative-to $repo_root_abs
    }
  } | flatten
}

def start-background-jobs [
  jjiles_cfg: record
]: nothing -> record<finalizers: list<closure>, witness: path> {
  mut finalizers: list<closure> = []

  let repo_root = ^jj root | path expand -n
  let jj_folder = $repo_root | path join ".jj"

  let globally_ignored = git-ignored $repo_root | append [".git/**"]

  let to_watch = $jjiles_cfg.watched? | default []
  let to_fetch = $jjiles_cfg.fetched? | default []

  let bg_jobs_witness = $jj_folder | path join jjiles_background_jobs

  if (not (($to_watch | is-empty) and ($to_fetch | is-empty))) {
    let watcher_pid = if ($bg_jobs_witness | path exists) {
      let pid_from_file = open $bg_jobs_witness | into int
      if (ps | any {$in.pid == $pid_from_file}) {
        $pid_from_file
      } else {
        std log debug $"Previous watcher process seems dead \(no process with pid ($pid_from_file)). Removing '($bg_jobs_witness)'"
        rm $bg_jobs_witness
      }
    }
    if ($watcher_pid != null) {
      std log info $"Watcher/fetcher jobs for this repo already started by another instance \(pid ($watcher_pid)). You can manually remove '($bg_jobs_witness)' if this watcher process is dead"
    } else {
      $finalizers = {
        rm -f $bg_jobs_witness
        std log debug $"($bg_jobs_witness) deleted"
      } | append $finalizers
      $nu.pid | save $bg_jobs_witness
      std log debug $"($bg_jobs_witness) created \(with pid ($nu.pid))"

      for entry in $to_watch {
        let folder = $repo_root | path join $entry.folder | path expand -n
        let pattern = $entry.pattern? | default "**"
        let ignored = $entry.ignore? | default [] |
          each {|i| $folder | path join $i | path relative-to $repo_root} |
          append $globally_ignored

        if not ($folder | path exists) {
          ( finalize $finalizers
              $"Folder ($folder) defined in [[jiles.watched]] does not exist in the repository" )
        }
        let job_id = job spawn {
          std log debug $"Job (job id): Watching `($folder)` for changes to ($pattern)"
          watch $folder --glob $pattern -q {|_op, path|
            let path = $path | path relative-to $repo_root

            # TODO: Not a great way to test if $path matches. Find a better way
            let ignored_paths = ($ignored | each {glob $in} | flatten | path relative-to $repo_root)

            if ($path in $ignored_paths) {
              std log debug $"Job (job id): Change to ($path) ignored"
            } else {
              # Will update the .jj folder and therefore trigger the jj watcher:
              let op_id = ^jj op log -n1 --no-graph -T 'id.short()'
              std log debug $"Job (job id): Changes to ($path) detected. Working copy snapshot. New op: ($op_id)"
            }
          }
        }
        $finalizers = {
          job kill $job_id
          std log debug $"Job ($job_id) killed"
        } | append $finalizers
      }

      for entry in $to_fetch {
        let remote = $entry.remote
        let branches = $entry.branches? | default ["*"]
        let dur = $entry.every? | default 5min | into duration

        let job_id = job spawn {
          std log debug $"Job (job id): Will fetch remote `($remote)` every ($dur)"
          loop {
            sleep $dur
            for b in $branches {
              ^jj git fetch --remote $remote --branch $"glob:($b)"
            }
            std log debug $"Job (job id): Fetched from remote ($remote)"
          }
        }
        $finalizers = {
          job kill $job_id
          std log debug $"Job ($job_id) killed"
        } | append $finalizers
      }
    }
  }
  {
    finalizers: $finalizers
    witness: $bg_jobs_witness
  }
}

# Get jjiles config
export def get-config [
  --jj-cfg (-j): record
    # Use this record as the jj config, instead of reading it from the jj user & repo config files.
    # Pass an empty record {} to get jjiles default config
] {
  let default_config = open $default_config_file
  let jj_cfg = if ($jj_cfg == null) {
    ^jj config list jjiles | from toml
  } else {$jj_cfg}
  $default_config | get jjiles | merge deep (
    $jj_cfg | get -o jjiles | default {}
  )
}

# Run jjiles watcher & fetcher jobs
#
# Subsequent calls to `jjiles` on the same repo will not start them
export def headless [
  --quiet (-q) # Do not print debug logs
] {
  # Print debug logs. Will be active only for this scope
  std log set-level (if $quiet {20} else {10})

  let jjiles_cfg = get-config
  let finalizers = (start-background-jobs $jjiles_cfg).finalizers
  if ($finalizers | is-not-empty) {
    sleep 0.1sec
    std log info $"Watching... Ctrl+c to stop"
    loop {
      match (input listen) {
        {modifiers: ["keymodifiers(control)"], code: "c"} => {
          break
        }
      }
    }
    finalize $finalizers
  }
}

# # JJiles. A JJ Watcher.
#
# Shows an interactive and auto-updating jj log that allows you to drill down
# into revisions. By default, it will refresh everytime a jj command modifies
# the repository. Additionally, JJiles can be told to automatically snapshot
# the working copy and refresh upon changes to a local folder with --watch.
#
# # User configuration
#
# JJiles UI, keybindings and colors can be configured via a `[jjiles]`
# section in your ~/.config/jj/config.toml.
#
# Run `jjiles get-config` to get the current config as a nushell record. See
# the `default-config.toml` file in this folder for more information.
export def --wrapped main [
  --help (-h) # Show this help page
  --revisions (-r): string@"nujj complete revision-ids" # Which revision(s) to log
  --template (-T): string # The alias of the jj log template to use. Will override
                          # the 'jjiles.templates.rev_log' if given
  --fuzzy # Use fuzzy finding instead of exact match
  --at-operation: string
    # An operation (from 'jj op log') at which to browse your repo.
    #
    # If given (even it is "@"), do not run any watching or fetching job. The
    # interface won't update upon changes to the repository or the working
    # copy, and the "@" operation will remain frozen the whole time to the
    # value its has when jjiles starts
  --at-op: string # Alias for --at-operation (to match jj CLI args)
  --height: int # Limit the height of the interface to some number of rows
  ...args # Extra args to pass to 'jj log' (--config for example)
]: nothing -> record<change_or_op_id: string, commit_id?: string, file?: string> {
  # Will contain closures that release all the resources acquired so far:
  mut finalizers: list<closure> = []

  let init_view = match $args {
    [op log] => {
      {view: "oplog", extra_args: []}
    }
    [op log ..$_rest] => {
      finalize $finalizers "Passing `jj op log` extra args is not supported"
    }
    [log ..$rest] => {
      {view: "revlog", extra_args: $rest}
    }
    _ => {
      {view: "revlog", extra_args: $args}
    }
  }

  let jj_cfg = ^jj config list --include-defaults | from toml
  let jjiles_cfg = get-config -j $jj_cfg
  let jj_cfg = get-needed-config-from-jj $jj_cfg

  # We retrieve the user default log revset:
  let revisions = if ($revisions == null) {
    $jj_cfg.revsets.log
  } else {
    $revisions
  }

  # We retrieve the user-defined templates, and generate from them
  # new templates from which fzf can reliably extract the data it needs:
  let templates = get-templates $jj_cfg $jjiles_cfg |
    update rev_log {if ($template == null) {$in} else {$template}} |
    update op_log {wrap-template "id.short()" "''" $in} |
    update rev_log {wrap-template "change_id.shortest(8)" "commit_id.shortest(8)" $in} |
    update evo_log {wrap-template "change_id.shortest(8)" "commit_id.shortest(8)" $in}

  let at_operation = $at_operation | default $at_op
  let do_watch_jj_repo = $at_operation == null
  let at_operation = if $do_watch_jj_repo {"@"} else {
    ^jj op log --at-operation $at_operation --no-graph -n1 --template 'id.short()' 
  }

  let is_watching_local_files = if $do_watch_jj_repo {
    let bg_jobs_fins = (start-background-jobs $jjiles_cfg).finalizers
    $finalizers = $bg_jobs_fins | append $finalizers
    $bg_jobs_fins | is-not-empty 
  } else {false}

  let tmp_dir = mktemp --directory
  $finalizers = {rm -rf $tmp_dir; std log debug $"($tmp_dir) deleted"} | append $finalizers
  
  let state_file = [$tmp_dir state.nuon] | path join

  {
    show_keybindings: $jjiles_cfg.interface.show-keybindings
    is_watching: {
      jj_repo: $do_watch_jj_repo
      local_files: $is_watching_local_files
    }
    templates: $templates
    jj_revlog_extra_args: $init_view.extra_args
    diff_config: $jjiles_cfg.diff
    color_config: ($jj_cfg.colors | merge $jjiles_cfg.colors.elements)
    revset: $revisions
    evolog_toggled_on: $jjiles_cfg.interface.evolog-toggled-on
    current_view: $init_view.view
    pos_in_oplog: 0
    selected_operation_id: $at_operation
    pos_in_revlog: {} # indexed by operation_id
    selected_change_id: null
    default_commit_id: null
    pos_in_evolog: {} # indexed by change_id
    selected_commit_id: null
    pos_in_files: {} # indexed by change_id or commit_id
  } | save $state_file
  std log debug $"($state_file) created"
  
  let fzf_port = port
  
  let back_keys = "shift-left,shift-tab,ctrl-h"
  let into_keys = "shift-right,tab,ctrl-l"
  let all_move_keys = $"shift-up,up,shift-down,down,($back_keys),($into_keys)"

  let on_load_started_commands = $"change-header\((ansi default_bold)...(ansi reset))+unbind\(($all_move_keys))"

  let jj_folder = ^jj root | path expand -n | path join ".jj"

  let jj_watcher_id = if $do_watch_jj_repo {
    let repo_folder = $jj_folder | path join repo
    let repo_folder = match ($repo_folder | path type) {
      "dir" => $repo_folder
      "file" => {
        open $repo_folder
      }
      _ => {
        error make {msg: $"($repo_folder) is neither a file not a folder"}
      }
    }
    ^jj debug snapshot
    let job_id = job spawn {
      std log debug $"Job (job id): Watching ($repo_folder)"
      watch $repo_folder -q {
        std log debug $"Job (job id): Changes to .jj folder detected"
        ( $"($on_load_started_commands)+(cmd update-list refresh $state_file "{n}" "{}")" |
            http post $"http://localhost:($fzf_port)"
        )
      }
    }
    $finalizers = {
      job kill $job_id
      std log debug $"Job ($job_id) killed"
    } | append $finalizers
    $job_id
  }

  let theme = match (deltau theme-flags) {
    ["--dark"] => "dark"
    ["--light"] => "light"
    _ => "16"
  }

  let main_bindings = {
    shift-up: up
    shift-down: down
    ctrl-space: jump
    $back_keys: [
      $on_load_started_commands
      (cmd update-list back $state_file "{n}" "{}")
      clear-query
      ...(cond (not $jjiles_cfg.interface.show-searchbar) hide-input)
    ]
    $into_keys: [
      $on_load_started_commands
      (cmd update-list into $state_file "{n}" "{}")
      clear-query
      ...(cond (not $jjiles_cfg.interface.show-searchbar) hide-input)
    ]
    resize: [
      "execute(tput reset)" # Avoids glitches in the fzf interface when terminal is resized
      (cmd -c transform on-load-finished $state_file "{n}")  # Refresh the header
      refresh-preview
    ]
    load: [
      (cmd -c transform on-load-finished $state_file)
      $"rebind\(($all_move_keys))"
    ]
    
    ctrl-v: [
      $on_load_started_commands
      (cmd toggle-evolog $state_file "{n}" "{}")
    ]
    ctrl-r: [
      "change-preview-window(right,68%|right,83%|right,50%)"
      show-header
      refresh-preview
    ]
    ctrl-b: [
      "change-preview-window(bottom,50%|bottom,75%|bottom,93%)"
      (if ($jjiles_cfg.interface.menu-position == bottom) {"hide-header"} else {"show-header"})
      refresh-preview
    ]
    ctrl-t: [
      "change-preview-window(top,50%|top,75%|top,93%)"
      (if ($jjiles_cfg.interface.menu-position == top) {"hide-header"} else {"show-header"})
      refresh-preview
    ]

    "ctrl-f,f3":     [clear-query, toggle-input]
    enter:           [toggle-preview, show-header]
    esc:             [close, show-header]
  }

  let conflicting_keys = $main_bindings | used-keys | join ($jjiles_cfg.bindings.fzf | used-keys) key
  if ($conflicting_keys | is-not-empty) {
    finalize $finalizers $"Keybindings for ($conflicting_keys | get key) cannot be overriden by user config"
  }

  let res = try {
    ^nu -n $fzf_callbacks update-list refresh $state_file |
    ( ^fzf
      --read0
      --delimiter (char us) --with-nth "1,4"
      --layout (match $jjiles_cfg.interface.menu-position {
        "top" => "reverse"
        "bottom" => "reverse-list"
      })
      ...(cond ($height != null) --height $height)
      --no-sort --track
      ...(cond (not $jjiles_cfg.interface.show-searchbar) --no-input)
      ...(cond (not $fuzzy) --exact)

      --ansi --color $theme
      --style $jjiles_cfg.interface.fzf-style
      --color ($jjiles_cfg.colors.fzf | to-fzf-colors $jjiles_cfg.colors.theme-mappings $theme)
      --highlight-line
      --header-first
      --header-border  $jjiles_cfg.interface.borders.header 
      --input-border   $jjiles_cfg.interface.borders.input
      --list-border    $jjiles_cfg.interface.borders.list
      --preview-border $jjiles_cfg.interface.borders.preview
      --prompt "Filter: "
      ...(if $jjiles_cfg.interface.show-keybindings {
        [--ghost "Ctrl+f: hide | Ctrl+p or n: navigate history"]
      } else {[]})
      --info inline-right

      --preview-window ([
        hidden
        ...(if $jjiles_cfg.interface.preview-line-wrapping {[wrap]} else {[]})
      ] | str join ",")
      --preview ([nu -n $fzf_callbacks preview $state_file "{}"] | str join " ")

      --history ($jj_folder | path join "jjiles_history")

      ...(cond ($jj_watcher_id != null) --listen $fzf_port)

      ...($main_bindings | merge $jjiles_cfg.bindings.fzf | to-fzf-bindings)
    )
  } catch {{error: $in}}
  ( finalize $finalizers
      (if (($res | describe) == record and
           $res.error? != null and
           $res.error.exit_code? != 130) {
           # fzf being Ctrl-C'd isn't an error for us. Thus we only rethrow other errors
        $res.error
      })
  )
  if ($res | describe) == string {
    $res | parsing get-matches | transpose k v | where v != "" | transpose -rd
  }
}
