# datatui - Nushell Plugin for Terminal UIs

A Nushell plugin that bridges Nu's data-centric world with terminal user interfaces using ratatui.

## Installation

1. Build the plugin:
   ```bash
   cargo build --release
   ```

2. Register the plugin with Nushell:
   ```bash
   plugin add ./target/release/nu_plugin_datatui
   ```

## Usage

### Basic Commands

#### Terminal Management
- `datatui init` - Initialize terminal for TUI mode
- `datatui terminate` - Restore terminal to normal mode

#### Event Handling
- `datatui events` - Get terminal events (blocking until events are available)

#### Widget Creation
- `datatui text --content "text" [--title "title"] [--wrap] [--scrollable]` - Create a text widget
- `datatui list --items ["item1", "item2"] [--selected 0] [--title "title"] [--scrollable]` - Create a list widget

#### Rendering
- `$widget | datatui render` - Render a single widget to the terminal

### Example: Simple Text Display

```nu
# Initialize terminal
datatui init

# Create and render a text widget
let text_widget = datatui text --content "Hello, World!" --title "Greeting"
$text_widget | datatui render

# Restore terminal
datatui terminate
```

### Example: File Browser

```nu
# Initialize terminal
datatui init

# Create a list of files
let files = (ls | get name)
let file_list = datatui list --items $files --selected 0 --title "Files" --scrollable

# Render the list
$file_list | datatui render

# Restore terminal
datatui terminate
```

### Example: Interactive Event Loop

```nu
# Initialize terminal
datatui init

let mut state = { cursor: 0, items: (ls | get name) }

loop {
    # Get events
    let events = datatui events

    # Process events and update state
    $state = $events | reduce --fold $state {|event, acc|
        match $event {
            {type: "key", key: "q"} => break
            {type: "key", key: "j"} => {
                $acc | update cursor (($acc.cursor + 1) | math min (($acc.items | length) - 1))
            }
            _ => $acc
        }
    }

    # Create and render widgets
    let file_list = datatui list --items $state.items --selected $state.cursor
    $file_list | datatui render
}

datatui terminate
```
