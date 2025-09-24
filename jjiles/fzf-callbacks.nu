# Used inside fzf by jjiles.nu

use deltau.nu
use parsing.nu

def main [] {}

# Replace the (char gs) inserted at the end of the template
# by a NULL that fzf will use as a multi-line record separator
def replace-template-ending [] {
  awk -v RS=(char gs) -v ORS='\0' '{gsub(/^[ \t\n]+|[ \t\n]+$/, ""); if (length($0) > 0) print}'
}

def --wrapped call-jj [--width (-w): int, ...args] {
  ( ^jj ...$args
      --color always
      --config $"width=($width)"
      --ignore-working-copy
  )
}

def print-oplog [width: int, state: record] {
  if $state.is_watching.jj_repo {
    ( print -n
        $"(ansi default_reverse)♡(ansi reset)  (char us)@(char us)(char us)"
        $"(ansi $state.color_config.operation)Live current operation(ansi reset)\n"
        $"│  (ansi default_italic)This operation will be updated whenever the `.jj/repo` folder is modified\n"
        $"│(char nul)"
    )
  }
  call-jj op log -w $width --template $state.templates.op_log | replace-template-ending
}

def print-revlog [width: int, state: record] {
  ( call-jj ...$state.jj_revlog_extra_args
      -w $width
      --revisions $state.revset
      --template $state.templates.rev_log
      --at-operation $state.selected_operation_id
  ) | replace-template-ending
}

def print-evolog [width: int, state: record] {
  ( call-jj evolog #...$state.jj_revlog_extra_args
      -w $width
      -r $state.selected_change_id
      --template $state.templates.evo_log
      --at-operation $state.selected_operation_id
  ) | replace-template-ending
}

# Get the id that will condition where to look for files
# (either change or commit id), depending on whether evolog is shown
def get-file-index [state] {
  if $state.evolog_toggled_on {$state.selected_commit_id} else {$state.selected_change_id}
}

def print-files [_width state] {
  let jj_out = (
    ^jj log
      -r (get-file-index $state)
      --no-graph
      --template
          $"self.diff\().files\().map\(|x|
              '(char us)' ++ change_id.shortest\(8) ++ '(char us)' ++
              commit_id.shortest\(8) ++ '(char us)' ++
              '● (char fs)(ansi $state.color_config.filepath)' ++ x.path\() ++ '(ansi reset)(char fs) [' ++ x.status\() ++ ']'
            ).join\('(char gs)')"
      --ignore-working-copy
      --at-operation $state.selected_operation_id
  ) | tr (char gs) \0 | complete
  if ($jj_out.stdout | is-empty) {
    false
  } else {
    print $jj_out.stdout
    true
  }
}

def do-update [transition state state_file fzf_pos fzf_selection_contents] {
  mut state = $state
  let width = $env.FZF_COLUMNS? | default (tput cols) | into int
  let matches = $fzf_selection_contents | str join " " | parsing get-matches
  
  # We store the current position of the cursor:
  let cell = match $state.current_view {
    "oplog"  => [pos_in_oplog]
    "revlog" => [pos_in_revlog $state.selected_operation_id] 
    "evolog" => [pos_in_evolog $state.selected_change_id]
    "files"  => [pos_in_files (get-file-index $state)]
  }
  if $cell != null and $fzf_pos != null {
    $state = $state | upsert ($cell | into cell-path) ($fzf_pos + 1)
  }
  
  # We update the state to perform the transition (if any happened):
  let updates = match [$state.current_view $state.evolog_toggled_on $transition $matches] {
    # From oplog into revlog:
    [oplog _ into {change_or_op_id: $op_id}] => {
      {
        current_view: revlog
        selected_operation_id: $op_id
      }
    }
    # From revlog back to oplog:
    [revlog _ back _] => {
      {current_view: oplog}
    }
    # From revlog into evolog/files:
    [revlog $evo into {change_or_op_id: $change_id, commit_id: $commit_id}] => {
      {
        current_view: (if $evo {"evolog"} else {"files"})
        selected_change_id: $change_id
        default_commit_id: $commit_id
        selected_commit_id: $commit_id
      }
    }
    # From evolog back into revlog:
    [evolog _ back _] => {
      {current_view: revlog}
    }
    # From evolog into files:
    [evolog _ into {commit_id: $commit_id}] => {
      {
        current_view: files
        selected_commit_id: $commit_id
      }
    }
    # From files back to evolog:
    [files true back _] => {
      {current_view: evolog}
    }
    # From files DIRECTLY back to revlog:
    [files false back _] => {
      {current_view: revlog}
    }
  }

  $state = $state | merge ($updates | default {})
  $state | save -f $state_file

  # We print the new view (or the refreshed current view) for fzf to parse:
  match $state.current_view {
    "oplog" => {
      print-oplog $width $state
    }
    "revlog" => {
      print-revlog $width $state
    }
    "evolog" => {
      print-evolog $width $state
    }
    "files" => {
      if (not (print-files $width $state)) {
        if $state.evolog_toggled_on {
          $state = $state | (update current_view evolog)
          $state | save -f $state_file
          print-evolog $width $state
        } else {
          $state = $state | (update current_view revlog)
          $state | save -f $state_file
          print-revlog $width $state
        }
      }
    }
  }
}

def --wrapped "main update-list" [
  transition: string
  state_file: path
  fzf_pos: int = 0
  ...contents: string
] {
  do-update $transition (open $state_file) $state_file $fzf_pos $contents
}

def "main toggle-evolog" [state_file: path, fzf_pos: int, ...contents] {
  mut state = open $state_file
  let cur_view = $state.current_view
  $state = $state |
    update evolog_toggled_on {not $in} |
    update current_view {if $cur_view == evolog {"revlog"} else {$cur_view}}
  $state | save -f $state_file
  do-update refresh $state $state_file (if $cur_view != evolog {$fzf_pos}) $contents
}

def call-delta [state file] {(
  deltau wrapper
    -s $state.diff_config.double-column-threshold
    --file-style "omit"
    --hunk-header-style
      (if $file != null {"line-number"} else {"file line-number"})
    --hunk-header-file-style $state.color_config.filepath
    --hunk-header-line-number-style ""
    --hunk-header-decoration-style "box"
    --paging never
)}

def preview-op [width state matches] {
  ( call-jj op show
      -w $width
      $matches.change_or_op_id
      --no-graph
      --stat --git
  ) | call-delta $state $matches.file?
}

def preview-rev-or-file [width state matches] {
  let template = if ($matches.file? == null) {
    $state.templates.rev_preview? | default ""
  } else {
    $state.templates.file_preview? | default "" | str replace -a "%FILE%" ($matches.file | $'"($in)"')
  }

  ( call-jj log
      -w $width
      -n1
      -r $matches.commit_id
      --template $template
      --no-graph
      --git
      --at-operation $state.selected_operation_id
      ...(if $matches.file? != null {[$matches.file]} else {[]})
  ) | call-delta $state $matches.file?
}

def preview-evo [width state matches] {
  ( call-jj evolog
      -w $width
      -n1
      -r $matches.commit_id
      --template $state.templates.evo_preview
      --no-graph
      --git
      --at-operation $state.selected_operation_id
  ) | call-delta $state $matches.file?
}

def --wrapped "main preview" [state_file: path, ...contents: string] {
  let state = open $state_file
  let width = $env.FZF_PREVIEW_COLUMNS? | default "80" | into int
  let matches = $contents | str join " " | parsing get-matches

  if $state.show_keybindings {
    let help = [[index key];
      ["Toggle wrap" "Ctrl+w"]
      ["Close"       "Enter  | Esc"]
      ["Move/resize" "Ctrl+r | Ctrl+t   | Ctrl+b"]
      ["Scroll"      "PageUp | PageDown | Ctrl+d | Ctrl+u"]
    ] | table --expand | lines | reject 1 2 |
      fill -a right -w ($env.FZF_PREVIEW_COLUMNS | into int) -c " " |
      str join "\n"
  
    print $"(ansi default_dimmed)($help)(ansi reset)"
  }

  match [$state.current_view $matches.change_or_op_id?] {
    [_ null] => {
      print $"(ansi default_italic)\(Nothing to show)(ansi reset)"
    }
    [oplog _] => {
      preview-op $width $state $matches
    }
    [evolog _] => {
      preview-evo $width $state $matches
    }
    _ => {
      preview-rev-or-file $width $state $matches
    }
  }
}

def "main on-load-finished" [state_file: path, cur_fzf_pos: int] {
  let state = open $state_file

  let new_fzf_pos = if ($state.has_passed_initial_load? == true) {
    match $state.current_view? {
      "oplog" => $state.pos_in_oplog
      "revlog" => {$state.pos_in_revlog | get -o $state.selected_operation_id}
      "evolog" => {$state.pos_in_evolog | get -o $state.selected_change_id}
      "files" => {$state.pos_in_files | get -o (get-file-index $state)}
    } | default 0
  } else {
    $state | upsert has_passed_initial_load true | save -f $state_file
    $cur_fzf_pos + 1
  }

  let colors = $state.color_config

  let ev_items = if $state.evolog_toggled_on {
    [EvoLog     Commit    ""  $colors.commit $state.selected_commit_id?]
  } else {
    ["(EvoLog)" "(Commit" ")" default_dimmed $state.default_commit_id? ]
  }

  let breadcrumbs = [
    [view   menu        prefix      suffix      color             value                       ];
    [oplog  OpLog       Op          ""          $colors.operation $state.selected_operation_id]
    [revlog RevLog      Rev         ""          $colors.revision  $state.selected_change_id?  ]
    [evolog $ev_items.0 $ev_items.1 $ev_items.2 $ev_items.3       $ev_items.4                 ]
    [files  Files       File        ""          $colors.filepath  null                        ]
  ]

  let before = $breadcrumbs | take until {$in.view == $state.current_view?}
  let num_before = $before | length
  let current = $breadcrumbs | get -o $num_before
  let after = $breadcrumbs | slice ($num_before + 1)..

  let header = [
    ...($before | each {|x|
      $"($x.prefix) (ansi $x.color)($x.value)(ansi reset)($x.suffix)"
    })
    ...(if ($current != null) {
      [$"(ansi $"($current.color)_reverse")($current.menu)(ansi reset)"]
    } else {[]})
    ...($after | each {|x|
      $"(ansi attr_dimmed)(ansi $x.color)($x.menu)(ansi reset)"
    })
  ] | str join " > "

  let width = $env.FZF_COLUMNS | into int | $in - 6  # to account for border
  let help_width = $width - ($header | ansi strip | str length)

  let help = [
    ...(if ($state.current_view == revlog) {
      [$"Revset: (ansi reset)(ansi $colors.revision)($state.revset)(ansi default_dimmed)"]
    } else {[]})
    ...(if $state.show_keybindings {
      [ "Shift+arrows: Navigate"
        "Ctrl+v: Toggle evolog"
        "Return: Toggle preview" ]
    } else {[]})
  ] | str join $" | " |
    fill -a right -w $help_width -c " "

  print ([
    $"change-header\(($header)  (ansi default_dimmed)($help)(ansi reset))"
    $"pos\(($new_fzf_pos))"
  ] | str join "+")
}
