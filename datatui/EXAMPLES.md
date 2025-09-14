# datatui Examples

## Simple File Browser

A basic file explorer demonstrating core datatui concepts:

```nu
#!/usr/bin/env nu

# Simple file browser example
def main [] {
  # Initialize terminal
  datatui init
  
  # Application state
  mut state = {
    current_dir: (pwd)
    items: (ls | select name type size)
    cursor: 0
    preview: ""
  }
  
  # Main event loop - user controls everything
  loop {
    # Get events from terminal
    let events = datatui events
    
    # Process events and update state
    $state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j"} => {
          let new_cursor = ($acc.cursor + 1) | math min (($acc.items | length) - 1)
          $acc | update cursor $new_cursor
        }
        {type: "key", key: "k"} => {
          let new_cursor = ($acc.cursor - 1) | math max 0
          $acc | update cursor $new_cursor
        }
        {type: "key", key: "Enter"} => {
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
        {type: "key", key: "q"} => break  # Exit loop
        _ => $acc
      }
    }
    
    # Create widgets using commands
    let selected_item = $state.items | get -o $state.cursor
    
    let file_list = datatui list 
      --items ($state.items | each {|item| 
        $"($item.name) (if $item.type == 'dir' {'/'} else {''})"
      })
      --selected $state.cursor
      --title $"Directory: ($state.current_dir)"
      --scrollable
    
    let preview_content = if ($selected_item.type? == "file") {
      $state.preview
    } else {
      $"($selected_item.name)\nType: ($selected_item.type)\nSize: ($selected_item.size)"
    }
    
    let preview = datatui text 
      --content $preview_content
      --wrap
      --title "Preview"
    
    # Render layout
    {
      layout: {
        direction: horizontal
        panes: [
          {widget: $file_list, size: "50%"}
          {widget: $preview, size: "*"}
        ]
      }
    } | datatui render
  }
  
  # Clean up terminal
  datatui terminate
}
```

## Process Monitor (nucess-style)

Multi-pane process management interface:

```nu
#!/usr/bin/env nu

def main [] {
  # Initialize terminal
  datatui init
  
  mut state = {
    processes: (ps | where pid != $nu.pid | select pid name cpu mem)
    selected: 0
    log_lines: []
    filter: ""
    view_mode: "list"  # "list" or "details"
  }
  
  loop {
    let events = datatui events
    
    $state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j"} => {
          $acc | update selected (($acc.selected + 1) | math min (($acc.processes | length) - 1))
        }
        {type: "key", key: "k"} => {
          $acc | update selected (($acc.selected - 1) | math max 0)
        }
        {type: "key", key: "Enter"} => {
          if $acc.view_mode == "list" {
            let selected_proc = $acc.processes | get $acc.selected
            $acc 
            | update view_mode "details"
            | update log_lines (get-process-logs $selected_proc.pid)
          } else { $acc }
        }
        {type: "key", key: "Escape"} => {
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
        {type: "key", key: "q"} => break
        _ => $acc
      }
    }
    
    let filtered_procs = if ($state.filter | is-empty) {
      $state.processes
    } else {
      $state.processes | where ($it.name | str contains $state.filter)
    }
    
    # Create widgets based on view mode
    if $state.view_mode == "list" {
      let status_bar = datatui text 
        --content $"Filter: ($state.filter) | Press '/' to filter, 'Enter' for details"
        --style "dim"
      
      let process_table = datatui table 
        --columns ["pid", "name", "cpu", "mem"]
        --rows ($filtered_procs | each {|p| [$p.pid $p.name $"($p.cpu)%" $p.mem]})
        --selected $state.selected
        --sortable
      
      {
        layout: {
          direction: vertical
          panes: [
            {widget: $status_bar, size: 1}
            {widget: $process_table, size: "*"}
          ]
        }
      } | datatui render
    } else {
      let selected_proc = $filtered_procs | get -o $state.selected
      
      let process_list = datatui list
        --items ($filtered_procs | each {|p| $"($p.pid): ($p.name)"})
        --selected $state.selected
        --title "Processes"
      
      let log_viewer = datatui text
        --content ($state.log_lines | str join "\n")
        --title $"Logs: ($selected_proc.name)"
        --scrollable
      
      {
        layout: {
          direction: horizontal
          panes: [
            {widget: $process_list, size: "30%"}
            {widget: $log_viewer, size: "*"}
          ]
        }
      } | datatui render
    }
  }
  
  datatui terminate
}

def get-process-logs [pid: int] {
  # Mock function - in real implementation, would read process logs
  [
    $"Process ($pid) started"
    "Loading configuration..."
    "Service running normally"
    $"Last heartbeat: (date now)"
  ]
}
```

## Data Table Viewer

Interactive table with sorting and filtering:

```nu
#!/usr/bin/env nu

def main [file: path] {
  let data = open $file
  
  datatui init
  
  mut state = {
    data: $data
    displayed_data: $data
    sort_column: null
    sort_direction: "asc"  # "asc" or "desc"
    filter: ""
    cursor: 0
    columns: ($data | first | columns)
  }
  
  loop {
    let events = datatui events
    
    $state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j"} => {
          $acc | update cursor (($acc.cursor + 1) | math min (($acc.displayed_data | length) - 1))
        }
        {type: "key", key: "k"} => {
          $acc | update cursor (($acc.cursor - 1) | math max 0)
        }
        {type: "key", key: "s"} => {
          # Sort menu - cycle through columns
          let columns = $acc.columns ++ [null]  # null = no sort
          let current_idx = $columns | enumerate | where item == $acc.sort_column | first | get -o index | default -1
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
              $acc.data | where ($it | get -o $col | default "" | into string | str contains $val)
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
        {type: "key", key: "q"} => break
        _ => $acc
      }
    }
    
    # Create widgets
    let header = datatui text
      --content ([
        $"File: ($file)"
        $"Rows: ($state.displayed_data | length) / ($state.data | length)"
        $"Sort: ($state.sort_column | default 'none') ($state.sort_direction)"
        $"Filter: ($state.filter)"
        ""
        "Controls: ↑↓ Navigate | s Sort | f Filter | q Quit"
      ] | str join " | ")
      --style "bold"
    
    let data_table = datatui table
      --columns $state.columns
      --rows ($state.displayed_data | each {|row|
        $state.columns | each {|col| $row | get -o $col | default "" | into string}
      })
      --selected $state.cursor
      --highlight-headers
    
    {
      layout: {
        direction: vertical
        panes: [
          {widget: $header, size: 2}
          {widget: $data_table, size: "*"}
        ]
      }
    } | datatui render
  }
  
  datatui terminate
}
```

## Streaming Log Viewer

Real-time streaming data with automatic updates:

```nu
#!/usr/bin/env nu

def main [log_file?: path] {
  let file = $log_file | default "/var/log/app.log"
  
  datatui init
  
  # Create streaming data sources - returns StreamId custom values
  let app_log_stream = datatui stream {|| tail -f $file}
  let error_log_stream = datatui stream {|| tail -f "/var/log/error.log"}
  let process_stream = datatui stream {|| ps | select pid name cpu | to json}
  
  mut state = {
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
  
  loop {
    let events = datatui events
    
    $state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "Tab"} => {
          $acc | update selected_tab (($acc.selected_tab + 1) mod 3)
        }
        {type: "key", key: "j"} => {
          $acc | update scroll_position (($acc.scroll_position + 1) | math max 0)
        }
        {type: "key", key: "k"} => {
          $acc | update scroll_position (($acc.scroll_position - 1) | math max 0)
        }
        {type: "key", key: "G"} => {
          $acc | update scroll_position -1 | update auto_scroll true  # -1 = end
        }
        {type: "key", key: "g"} => {
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
        {type: "key", key: "q"} => break
        _ => $acc
      }
    }
    
    let tabs = ["App Log", "Error Log", "Processes"]
    
    # Create tab bar
    let tab_bar = datatui tabs
      --tabs $tabs
      --selected $state.selected_tab
    
    # Create main content based on selected tab
    let main_widget = match $state.selected_tab {
      0 | 1 => {  # Log viewers
        let stream = if $state.selected_tab == 0 {
          $state.streams.app_log
        } else {
          $state.streams.error_log
        }
        
        datatui streaming-text
          --stream $stream
          --filter $state.filter
          --scroll-position $state.scroll_position
          --auto-scroll $state.auto_scroll
          --title ($tabs | get $state.selected_tab)
          --wrap
      }
      2 => {  # Process table
        datatui streaming-table
          --stream $state.streams.processes
          --columns ["pid", "name", "cpu"]
          --refresh-rate "2sec"
          --title "Processes"
      }
    }
    
    # Status bar
    let status = datatui text
      --content ([
        $"Filter: ($state.filter)"
        $"Auto-scroll: ($state.auto_scroll)"
        "[Tab] Switch | [/] Filter | [a] Toggle auto-scroll | [r] Refresh | [q] Quit"
      ] | str join " | ")
      --style "dim"
    
    {
      layout: {
        direction: vertical
        panes: [
          {widget: $tab_bar, size: 1}
          {widget: $main_widget, size: "*"}
          {widget: $status, size: 1}
        ]
      }
    } | datatui render
  }
  
  datatui terminate
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

# Usage in main loop event processing
loop {
  let events = datatui events
  $state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "j"} => (navigate-list $acc "down")
      {type: "key", key: "k"} => (navigate-list $acc "up")
      {type: "key", key: "g"} => (navigate-list $acc "home")
      {type: "key", key: "G"} => (navigate-list $acc "end")
      _ => $acc
    }
  }
  # ... render widgets
}
```

### Widget Composition

```nu
# Reusable widget builders
def build-file-list [files: list<record>, selected: int] {
  datatui list
    --items ($files | each {|f| $"($f.name) (if $f.type == 'dir' {'/'} else {''})"})
    --selected $selected
    --scrollable
}

def build-preview-pane [content: string] {
  datatui text
    --content $content
    --wrap
    --scrollable
    --title "Preview"
}

# Usage in main loop
loop {
  let events = datatui events
  # ... process events ...
  
  let file_list = build-file-list $state.files $state.cursor
  let preview = build-preview-pane $state.preview
  
  {
    layout: {
      direction: horizontal
      panes: [
        {widget: $file_list, size: "40%"}
        {widget: $preview, size: "*"}
      ]
    }
  } | datatui render
}
```