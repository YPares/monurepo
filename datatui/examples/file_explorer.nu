#!/usr/bin/env -S nu --plugins "[./target/debug/nu_plugin_datatui]"

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
    continue: true
  }
  
  # Main event loop
  while $state.continue {
    # Get events from terminal
    let events = datatui events --timeout 0.2sec
    
    # Process events and update state
    $state = $events | reduce --fold $state {|event, acc|
      match $event {
        {type: "key", key: "j"} => {
          let new_cursor = [($acc.cursor + 1) (($acc.items | length) - 1)] | math min 
          $acc | update cursor $new_cursor
        }
        {type: "key", key: "k"} => {
          let new_cursor = [($acc.cursor - 1) 0] | math max 
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
        {type: "key", key: "q"} => {
          $acc | update continue false
        }
        _ => $acc
      }
    }
    
    # Create widgets using commands
    let selected_item = $state.items | get -o $state.cursor
    
    let file_list = ( datatui list 
      --items ($state.items | each {|item| 
        $"($item.name)(if $item.type == 'dir' {'/'} else {''})"
      })
      --selected $state.cursor
      --title $"Directory: ($state.current_dir)"
      --scrollable
    )
    let preview_content = if ($selected_item.type? == "file") {
      $state.preview
    } else {
      $"($selected_item.name)\nType: ($selected_item.type)\nSize: ($selected_item.size)"
    }
    
    let preview = ( datatui text 
      --content $preview_content
      --wrap
      --title "Preview"
    )
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
