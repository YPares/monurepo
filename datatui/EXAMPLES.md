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
  
  let render = {|state|
    let filtered_procs = if ($state.filter | is-empty) {
      $state.processes
    } else {
      $state.processes | where ($it.name | str contains $state.filter)
    }
    
    match $state.view_mode {
      "list" => {
        {
          layout: {
            direction: vertical
            panes: [
              {
                widget: {
                  type: "text"
                  content: $"Filter: ($state.filter) | Press '/' to filter, 'Enter' for details"
                  style: "dim"
                }
                size: 1
              }
              {
                widget: {
                  type: "table"
                  columns: ["pid", "name", "cpu", "mem"]
                  rows: ($filtered_procs | each {|p| [$p.pid $p.name $"($p.cpu)%" $p.mem]})
                  selected: $state.selected
                  sortable: true
                }
                size: "*"
              }
            ]
          }
        }
      }
      "details" => {
        let selected_proc = $filtered_procs | get -i $state.selected
        {
          layout: {
            direction: horizontal
            panes: [
              {
                widget: {
                  type: "list"
                  items: ($filtered_procs | each {|p| $"($p.pid): ($p.name)"})
                  selected: $state.selected
                  title: "Processes"
                }
                size: "30%"
              }
              {
                widget: {
                  type: "text"
                  content: ($state.log_lines | str join "\n")
                  title: $"Logs: ($selected_proc.name)"
                  scrollable: true
                }
                size: "*"
              }
            ]
          }
        }
      }
    }
  }
  
  let events = {
    on_key: {
      "j": {|state| $state | update selected (($state.selected + 1) | math min (($state.processes | length) - 1))}
      "k": {|state| $state | update selected (($state.selected - 1) | math max 0)}
      "enter": {|state|
        if $state.view_mode == "list" {
          let selected_proc = $state.processes | get $state.selected
          $state 
          | update view_mode "details"
          | update log_lines (get-process-logs $selected_proc.pid)
        } else {
          $state
        }
      }
      "esc": {|state| $state | update view_mode "list" | update filter ""}
      "/": {|state|
        let filter = (input "Filter processes: ")
        $state | update filter $filter
      }
      "r": {|state|
        # Refresh process list
        $state | update processes (ps | where pid != $nu.pid | select pid name cpu mem)
      }
      "q": {|state| exit}
    }
  }
  
  datatui run --state $initial_state --render $render --events $events
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
  
  let render = {|state|
    {
      layout: {
        direction: vertical
        panes: [
          # Header with controls
          {
            widget: {
              type: "text"
              content: ([
                $"File: ($file)"
                $"Rows: ($state.displayed_data | length) / ($state.data | length)"
                $"Sort: ($state.sort_column // 'none') ($state.sort_direction)"
                $"Filter: ($state.filter)"
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
              columns: $state.columns
              rows: ($state.displayed_data | each {|row|
                $state.columns | each {|col| $row | get -i $col | into string}
              })
              selected: $state.cursor
              highlight_headers: true
            }
            size: "*"
          }
        ]
      }
    }
  }
  
  let events = {
    on_key: {
      "j": {|state| 
        $state | update cursor (($state.cursor + 1) | math min (($state.displayed_data | length) - 1))
      }
      "k": {|state|
        $state | update cursor (($state.cursor - 1) | math max 0)
      }
      "s": {|state|
        # Sort menu - cycle through columns
        let columns = $state.columns ++ [null]  # null = no sort
        let current_idx = $columns | enumerate | where item == $state.sort_column | first | get -i index | default -1
        let next_idx = ($current_idx + 1) mod ($columns | length)
        let next_column = $columns | get $next_idx
        
        let new_direction = if $next_column == $state.sort_column {
          if $state.sort_direction == "asc" { "desc" } else { "asc" }
        } else {
          "asc"
        }
        
        let sorted_data = if $next_column == null {
          $state.data
        } else {
          if $new_direction == "asc" {
            $state.data | sort-by $next_column
          } else {
            $state.data | sort-by $next_column | reverse
          }
        }
        
        $state 
        | update sort_column $next_column
        | update sort_direction $new_direction
        | update displayed_data $sorted_data
        | update cursor 0
      }
      "f": {|state|
        let filter = input "Filter (column:value): "
        let filtered_data = if ($filter | is-empty) {
          $state.data
        } else {
          # Simple filter: column_name:value
          let parts = $filter | split column ":"
          if ($parts | length) == 2 {
            let col = $parts | first
            let val = $parts | last
            $state.data | where ($it | get -i $col | into string | str contains $val)
          } else {
            $state.data
          }
        }
        
        $state
        | update filter $filter
        | update displayed_data $filtered_data
        | update cursor 0
      }
      "c": {|state|
        # Clear filter
        $state
        | update filter ""
        | update displayed_data $state.data
        | update cursor 0
      }
      "q": {|state| exit}
    }
  }
  
  datatui run --state $initial_state --render $render --events $events
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
  
  let render = {|state|
    let tabs = ["Overview", "Processes", "Network"]
    
    {
      layout: {
        direction: vertical
        panes: [
          # Tab bar
          {
            widget: {
              type: "tabs"
              tabs: $tabs
              selected: $state.selected_tab
            }
            size: 1
          }
          
          # Tab content
          {
            widget: (match $state.selected_tab {
              0 => {  # Overview
                type: "layout"
                direction: vertical
                panes: [
                  {
                    widget: {
                      type: "gauge"
                      value: $state.memory_usage
                      label: "Memory Usage"
                      style: "green"
                    }
                    size: 3
                  }
                  {
                    widget: {
                      type: "chart"
                      data: $state.cpu_usage
                      title: "CPU Usage Over Time"
                      type: "line"
                    }
                    size: "*"
                  }
                ]
              }
              1 => {  # Processes
                type: "table"
                columns: ["pid", "name", "cpu", "memory"]
                rows: ($state.processes | each {|p| 
                  [$p.pid $p.name $"($p.cpu)%" $"($p.memory)MB"]
                })
                sortable: true
              }
              2 => {  # Network
                type: "text"
                content: ([
                  "Network I/O Statistics"
                  ""
                  $"RX: ($state.network_io.rx) bytes"
                  $"TX: ($state.network_io.tx) bytes" 
                  ""
                  $"Last Update: ($state.last_update)"
                ] | str join "\n")
              }
            })
            size: "*"
          }
          
          # Status bar
          {
            widget: {
              type: "text"
              content: $"[Tab] Switch tabs | [r] Refresh | [q] Quit | Updated: ($state.last_update | date humanize)"
              style: "dim"
            }
            size: 1
          }
        ]
      }
    }
  }
  
  let events = {
    on_key: {
      "tab": {|state| 
        $state | update selected_tab (($state.selected_tab + 1) mod 3)
      }
      "r": {|state|
        # Manual refresh
        refresh-system-stats $state
      }
      "q": {|state| exit}
    }
    
    # Auto-refresh every 2 seconds
    on_timer: {|state|
      if ((date now) - $state.last_update) > $state.update_interval {
        refresh-system-stats $state
      } else {
        $state
      }
    }
  }
  
  datatui run --state $initial_state --render $render --events $events
}

def refresh-system-stats [state] {
  $state
  | update memory_usage (sys mem | get used | math round)
  | update processes (ps | select pid name cpu mem | first 10)
  | update cpu_usage ($state.cpu_usage ++ [(sys cpu | get cpu | math avg)] | last 20)
  | update last_update (date now)
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

# Usage in event handlers
let events = {
  on_key: {
    "j": {|state| navigate-list $state "down"}
    "k": {|state| navigate-list $state "up"}
    "g": {|state| navigate-list $state "home"}
    "G": {|state| navigate-list $state "end"}
  }
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
let render = {|state|
  {
    layout: {
      direction: horizontal
      panes: [
        {widget: (build-file-list $state.files $state.cursor), size: "40%"}
        {widget: (build-preview-pane $state.preview), size: "*"}
      ]
    }
  }
}
```