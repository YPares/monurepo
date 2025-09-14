# datatui Examples

## Simple File Browser

A basic file explorer demonstrating core datatui concepts:

```nu
#!/usr/bin/env nu

# Simple file browser example
def main [] {
  let initial_state = {
    current_dir: (pwd)
    items: (ls | select name type size)
    cursor: 0
    preview: ""
  }
  
  let render = {|state, events|
    # Process events first
    let new_state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j", widget_id: "file_list"} => {
          let new_cursor = ($acc.cursor + 1) | math min (($acc.items | length) - 1)
          $acc | update cursor $new_cursor
        }
        {type: "key", key: "k", widget_id: "file_list"} => {
          let new_cursor = ($acc.cursor - 1) | math max 0
          $acc | update cursor $new_cursor
        }
        {type: "key", key: "enter", widget_id: "file_list"} => {
          let selected = $acc.items | get $acc.cursor
          if $selected.type == "dir" {
            cd $selected.name
            {
              current_dir: (pwd)
              items: (ls | select name type size)
              cursor: 0
              preview: ""
            }
          } else {
            $acc | update preview (open $selected.name | str substring 0..1000)
          }
        }
        {type: "select", index: $idx, widget_id: "file_list"} => {
          $acc | update cursor $idx
        }
        {type: "key", key: "q"} => (exit)
        _ => $acc
      }
    }
    
    # Build UI description
    let selected_item = $new_state.items | get -i $new_state.cursor
    
    {
      state: $new_state
      ui: {
        layout: {
          direction: horizontal
          panes: [
            {
              widget: {
                type: "list"
                id: "file_list"    # Required for event targeting
                items: ($new_state.items | each {|item| 
                  $"($item.name) (if $item.type == 'dir' {'/'} else {'')"
                })
                selected: $new_state.cursor
                title: $"Directory: ($new_state.current_dir)"
              }
              size: "50%"
            }
            {
              widget: {
                type: "text"
                content: (if ($selected_item.type? == "file") {
                  $new_state.preview
                } else {
                  $"($selected_item.name)\nType: ($selected_item.type)\nSize: ($selected_item.size)"
                })
                wrap: true
                title: "Preview"
              }
              size: "*"
            }
          ]
        }
      }
    }
  }
  
  datatui run --state $initial_state --render $render
}
```

## Process Monitor (nucess-style)

Multi-pane process management interface:

```nu
#!/usr/bin/env nu

def main [] {
  let initial_state = {
    processes: (ps | where pid != $nu.pid | select pid name cpu mem)
    selected: 0
    log_lines: []
    filter: ""
    view_mode: "list"  # "list" or "details"
  }
  
  let render = {|state, events|
    # Process events first
    let new_state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j", widget_id: "process_table"} => {
          $acc | update selected (($acc.selected + 1) | math min (($acc.processes | length) - 1))
        }
        {type: "key", key: "k", widget_id: "process_table"} => {
          $acc | update selected (($acc.selected - 1) | math max 0)
        }
        {type: "key", key: "enter", widget_id: "process_table"} => {
          if $acc.view_mode == "list" {
            let selected_proc = $acc.processes | get $acc.selected
            $acc 
            | update view_mode "details"
            | update log_lines (get-process-logs $selected_proc.pid)
          } else { $acc }
        }
        {type: "key", key: "esc"} => {
          $acc | update view_mode "list" | update filter ""
        }
        {type: "key", key: "/"} => {
          let filter = (input "Filter processes: ")
          $acc | update filter $filter
        }
        {type: "key", key: "r"} => {
          # Refresh process list
          $acc | update processes (ps | where pid != $nu.pid | select pid name cpu mem)
        }
        {type: "key", key: "q"} => (exit)
        _ => $acc
      }
    }
    
    let filtered_procs = if ($new_state.filter | is-empty) {
      $new_state.processes
    } else {
      $new_state.processes | where ($it.name | str contains $new_state.filter)
    }
    
    {
      state: $new_state
      ui: {
        layout: (match $new_state.view_mode {
          "list" => {
            direction: vertical
            panes: [
              {
                widget: {
                  type: "text"
                  content: $"Filter: ($new_state.filter) | Press '/' to filter, 'Enter' for details"
                  style: "dim"
                }
                size: 1
              }
              {
                widget: {
                  type: "table"
                  id: "process_table"    # Required for event targeting
                  columns: ["pid", "name", "cpu", "mem"]
                  rows: ($filtered_procs | each {|p| [$p.pid $p.name $"($p.cpu)%" $p.mem]})
                  selected: $new_state.selected
                  sortable: true
                }
                size: "*"
              }
            ]
          }
          "details" => {
            let selected_proc = $filtered_procs | get -i $new_state.selected
            {
              direction: horizontal
              panes: [
                {
                  widget: {
                    type: "list"
                    id: "process_list"
                    items: ($filtered_procs | each {|p| $"($p.pid): ($p.name)"})
                    selected: $new_state.selected
                    title: "Processes"
                  }
                  size: "30%"
                }
                {
                  widget: {
                    type: "text"
                    content: ($new_state.log_lines | str join "\n")
                    title: $"Logs: ($selected_proc.name)"
                    scrollable: true
                  }
                  size: "*"
                }
              ]
            }
          }
        })
      }
    }
  }
  
  datatui run --state $initial_state --render $render
}

def get-process-logs [pid: int] {
  # Mock function - in real implementation, would read process logs
  [
    $"Process ($pid) started"
    "Loading configuration..."
    "Service running normally"
    "Last heartbeat: (date now)"
  ]
}
```

## Data Table Viewer

Interactive table with sorting and filtering:

```nu
#!/usr/bin/env nu

def main [file: path] {
  let data = open $file
  
  let initial_state = {
    data: $data
    displayed_data: $data
    sort_column: null
    sort_direction: "asc"  # "asc" or "desc"
    filter: ""
    cursor: 0
    columns: ($data | first | columns)
  }
  
  let render = {|state, events|
    # Process events first
    let new_state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j", widget_id: "data_table"} => {
          $acc | update cursor (($acc.cursor + 1) | math min (($acc.displayed_data | length) - 1))
        }
        {type: "key", key: "k", widget_id: "data_table"} => {
          $acc | update cursor (($acc.cursor - 1) | math max 0)
        }
        {type: "key", key: "s"} => {
          # Sort menu - cycle through columns
          let columns = $acc.columns ++ [null]  # null = no sort
          let current_idx = $columns | enumerate | where item == $acc.sort_column | first | get -i index | default -1
          let next_idx = ($current_idx + 1) mod ($columns | length)
          let next_column = $columns | get $next_idx
          
          let new_direction = if $next_column == $acc.sort_column {
            if $acc.sort_direction == "asc" { "desc" } else { "asc" }
          } else {
            "asc"
          }
          
          let sorted_data = if $next_column == null {
            $acc.data
          } else {
            if $new_direction == "asc" {
              $acc.data | sort-by $next_column
            } else {
              $acc.data | sort-by $next_column | reverse
            }
          }
          
          $acc 
          | update sort_column $next_column
          | update sort_direction $new_direction
          | update displayed_data $sorted_data
          | update cursor 0
        }
        {type: "key", key: "f"} => {
          let filter = input "Filter (column:value): "
          let filtered_data = if ($filter | is-empty) {
            $acc.data
          } else {
            # Simple filter: column_name:value
            let parts = $filter | split column ":"
            if ($parts | length) == 2 {
              let col = $parts | first
              let val = $parts | last
              $acc.data | where ($it | get -i $col | into string | str contains $val)
            } else {
              $acc.data
            }
          }
          
          $acc
          | update filter $filter
          | update displayed_data $filtered_data
          | update cursor 0
        }
        {type: "key", key: "c"} => {
          # Clear filter
          $acc
          | update filter ""
          | update displayed_data $acc.data
          | update cursor 0
        }
        {type: "key", key: "q"} => (exit)
        _ => $acc
      }
    }
    
    {
      state: $new_state
      ui: {
        layout: {
          direction: vertical
          panes: [
            # Header with controls
            {
              widget: {
                type: "text"
                content: ([
                  $"File: ($file)"
                  $"Rows: ($new_state.displayed_data | length) / ($new_state.data | length)"
                  $"Sort: ($new_state.sort_column // 'none') ($new_state.sort_direction)"
                  $"Filter: ($new_state.filter)"
                  ""
                  "Controls: ↑↓ Navigate | s Sort | f Filter | q Quit"
                ] | str join " | ")
                style: "bold"
              }
              size: 2
            }
            
            # Main data table
            {
              widget: {
                type: "table"
                id: "data_table"    # Required for event targeting
                columns: $new_state.columns
                rows: ($new_state.displayed_data | each {|row|
                  $new_state.columns | each {|col| $row | get -i $col | into string}
                })
                selected: $new_state.cursor
                highlight_headers: true
              }
              size: "*"
            }
          ]
        }
      }
    }
  }
  
  datatui run --state $initial_state --render $render
}
```

## Real-time System Monitor

Live updating dashboard:

```nu
#!/usr/bin/env nu

def main [] {
  let initial_state = {
    cpu_usage: []
    memory_usage: 0
    processes: []
    network_io: {rx: 0, tx: 0}
    last_update: (date now)
    update_interval: 2sec
    selected_tab: 0  # 0=overview, 1=processes, 2=network
  }
  
  let render = {|state, events|
    # Process events first
    let new_state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "Tab"} => {
          $acc | update selected_tab (($acc.selected_tab + 1) mod 3)
        }
        {type: "key", key: "r"} => {
          # Manual refresh
          refresh-system-stats $acc
        }
        {type: "timer"} => {
          # Auto-refresh every 2 seconds
          if ((date now) - $acc.last_update) > $acc.update_interval {
            refresh-system-stats $acc
          } else {
            $acc
          }
        }
        {type: "key", key: "q"} => (exit)
        _ => $acc
      }
    }
    
    let tabs = ["Overview", "Processes", "Network"]
    
    {
      state: $new_state
      ui: {
        layout: {
          direction: vertical
          panes: [
            # Tab bar
            {
              widget: {
                type: "tabs"
                id: "tab_bar"
                tabs: $tabs
                selected: $new_state.selected_tab
              }
              size: 1
            }
            
            # Tab content
            {
              widget: (match $new_state.selected_tab {
                0 => {  # Overview
                  type: "layout"
                  direction: vertical
                  panes: [
                    {
                      widget: {
                        type: "gauge"
                        value: $new_state.memory_usage
                        label: "Memory Usage"
                        style: "green"
                      }
                      size: 3
                    }
                    {
                      widget: {
                        type: "chart"
                        data: $new_state.cpu_usage
                        title: "CPU Usage Over Time"
                        type: "line"
                      }
                      size: "*"
                    }
                  ]
                }
                1 => {  # Processes
                  type: "table"
                  id: "process_table"
                  columns: ["pid", "name", "cpu", "memory"]
                  rows: ($new_state.processes | each {|p| 
                    [$p.pid $p.name $"($p.cpu)%" $"($p.memory)MB"]
                  })
                  sortable: true
                }
                2 => {  # Network
                  type: "text"
                  content: ([
                    "Network I/O Statistics"
                    ""
                    $"RX: ($new_state.network_io.rx) bytes"
                    $"TX: ($new_state.network_io.tx) bytes" 
                    ""
                    $"Last Update: ($new_state.last_update)"
                  ] | str join "\n")
                }
              })
              size: "*"
            }
            
            # Status bar
            {
              widget: {
                type: "text"
                content: $"[Tab] Switch tabs | [r] Refresh | [q] Quit | Updated: ($new_state.last_update | date humanize)"
                style: "dim"
              }
              size: 1
            }
          ]
        }
      }
    }
  }
  
  datatui run --state $initial_state --render $render
}

def refresh-system-stats [state] {
  $state
  | update memory_usage (sys mem | get used | math round)
  | update processes (ps | select pid name cpu mem | first 10)
  | update cpu_usage ($state.cpu_usage ++ [(sys cpu | get cpu | math avg)] | last 20)
  | update last_update (date now)
}
```

## Streaming Log Viewer

Streaming data with automatic updates:

```nu
#!/usr/bin/env nu

def main [log_file?: path] {
  let file = $log_file | default "/var/log/app.log"
  
  # Create streaming data sources - returns StreamId custom values
  let app_log_stream = datatui stream {|| tail -f $file}
  let error_log_stream = datatui stream {|| tail -f "/var/log/error.log"}
  let process_stream = datatui stream {|| ps | select pid name cpu | to json}
  
  let initial_state = {
    # Store StreamIds, not the data itself
    streams: {
      app_log: $app_log_stream
      error_log: $error_log_stream
      processes: $process_stream
    }
    
    # UI state
    selected_tab: 0  # 0=app_log, 1=error_log, 2=processes
    scroll_position: 0
    auto_scroll: true
    filter: ""
  }
  
  let render = {|state, events|
    # Process events first
    let new_state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "Tab"} => {
          $acc | update selected_tab (($acc.selected_tab + 1) mod 3)
        }
        {type: "key", key: "j", widget_id: "log_viewer"} => {
          $acc | update scroll_position (($acc.scroll_position + 1) | math max 0)
        }
        {type: "key", key: "k", widget_id: "log_viewer"} => {
          $acc | update scroll_position (($acc.scroll_position - 1) | math max 0)
        }
        {type: "key", key: "G", widget_id: "log_viewer"} => {
          $acc | update scroll_position -1 | update auto_scroll true  # -1 = end
        }
        {type: "key", key: "g", widget_id: "log_viewer"} => {
          $acc | update scroll_position 0 | update auto_scroll false
        }
        {type: "key", key: "a"} => {
          $acc | update auto_scroll (not $acc.auto_scroll)
        }
        {type: "key", key: "r"} => {
          # Refresh streams by creating new ones - old ones get GC'd automatically
          let new_app_log = datatui stream {|| tail -f $file}
          let new_error_log = datatui stream {|| tail -f "/var/log/error.log"}
          let new_processes = datatui stream {|| ps | select pid name cpu | to json}
          
          $acc | update streams {
            app_log: $new_app_log
            error_log: $new_error_log
            processes: $new_processes
          }
        }
        {type: "key", key: "/"} => {
          let filter = input "Filter: "
          $acc | update filter $filter
        }
        {type: "key", key: "c"} => {
          $acc | update filter ""
        }
        {type: "key", key: "q"} => (exit)
        _ => $acc
      }
    }
    
    let tabs = ["App Log", "Error Log", "Processes"]
    
    {
      state: $new_state
      ui: {
        layout: {
          direction: vertical
          panes: [
            # Tab bar
            {
              widget: {
                type: "tabs"
                id: "tab_bar"
                tabs: $tabs
                selected: $new_state.selected_tab
              }
              size: 1
            }
            
            # Main content based on selected tab
            {
              widget: (match $new_state.selected_tab {
                0 | 1 => {  # Log viewers
                  let stream = if $new_state.selected_tab == 0 {
                    $new_state.streams.app_log
                  } else {
                    $new_state.streams.error_log
                  }
                  
                  {
                    type: "streaming_text"
                    id: "log_viewer"    # Required for event targeting
                    stream: $stream     # Reference StreamId
                    filter: $new_state.filter
                    scroll_position: $new_state.scroll_position
                    auto_scroll: $new_state.auto_scroll
                    title: ($tabs | get $new_state.selected_tab)
                    wrap: true
                  }
                }
                2 => {  # Process table
                  type: "streaming_table"
                  id: "process_table"
                  stream: $new_state.streams.processes
                  columns: ["pid", "name", "cpu"]
                  refresh_rate: "2sec"
                  title: "Processes"
                }
              })
              size: "*"
            }
            
            # Status bar
            {
              widget: {
                type: "text"
                content: ([
                  $"Filter: ($new_state.filter)"
                  $"Auto-scroll: ($new_state.auto_scroll)"
                  "[Tab] Switch | [/] Filter | [a] Toggle auto-scroll | [r] Refresh | [q] Quit"
                ] | str join " | ")
                style: "dim"
              }
              size: 1
            }
          ]
        }
      }
    }
  }
  
  datatui run --state $initial_state --render $render
}
```

## Usage Patterns

### State Management Best Practices

```nu
# Good: Immutable updates
let new_state = $state | update cursor ($state.cursor + 1)

# Good: Complex transformations with pipelines
let new_state = $state 
  | update items (filter-items $state.items $state.filter)
  | update cursor (math min $state.cursor (($new_items | length) - 1))

# Good: Conditional updates
let new_state = if $should_update {
  $state | update data (fetch-new-data)
} else {
  $state
}
```

### Event Handler Patterns

```nu
# Reusable navigation handlers
def navigate-list [state: record, direction: string] {
  let current = $state.cursor
  let max_index = ($state.items | length) - 1
  
  let new_cursor = match $direction {
    "up" => ($current - 1) | math max 0
    "down" => ($current + 1) | math min $max_index
    "home" => 0
    "end" => $max_index
  }
  
  $state | update cursor $new_cursor
}

# Usage in render function event processing
let render = {|state, events|
  let new_state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "j", widget_id: "main_list"} => (navigate-list $acc "down")
      {type: "key", key: "k", widget_id: "main_list"} => (navigate-list $acc "up")
      {type: "key", key: "g", widget_id: "main_list"} => (navigate-list $acc "home")
      {type: "key", key: "G", widget_id: "main_list"} => (navigate-list $acc "end")
      _ => $acc
    }
  }
  # ... return {state: $new_state, ui: ...}
}
```

### Widget Composition

```nu
# Reusable widget builders
def build-file-list [files: list<record>, selected: int] {
  {
    type: "list"
    items: ($files | each {|f| $"($f.name) (if $f.type == 'dir' {'/'} else {''})"})
    selected: $selected
    scrollable: true
  }
}

def build-preview-pane [content: string] {
  {
    type: "text"
    content: $content
    wrap: true
    scrollable: true
    title: "Preview"
  }
}

# Usage in render function
let render = {|state, events|
  # Process events first...
  let new_state = $events | reduce --fold $state {|event, acc|
    # ... event processing ...
  }
  
  {
    state: $new_state
    ui: {
      layout: {
        direction: horizontal
        panes: [
          {widget: (build-file-list $new_state.files $new_state.cursor), size: "40%"}
          {widget: (build-preview-pane $new_state.preview), size: "*"}
        ]
      }
    }
  }
}
```