# datatui: A Nushell Ratatui Plugin

## Vision

`datatui` is a low-level Nushell plugin that bridges Nu's data-centric world with terminal user interfaces. It provides primitive TUI widgets and layout management, allowing Nu scripts to build interactive applications using a reactive, state-driven architecture.

**Core Philosophy**: Keep the plugin simple and generic. Application logic stays in Nushell, datatui only handles TUI rendering and event dispatch.

## Use Cases

### Confirmed Use Cases
1. **jjiles**: Interactive revision browser for Jujutsu version control
   - Multi-view navigation (OpLog → RevLog → EvoLog → Files)
   - Streaming content with real-time updates
   - Complex keybinding system

2. **nucess**: Process management TUI (Nushell version of mprocs)
   - Multi-pane layout for process logs
   - Process control (start/stop/restart)
   - Real-time log streaming

### Future Potential
- File explorers
- System monitors
- Interactive data viewers
- Configuration UIs

## Architecture

### User-Controlled Immediate Mode

Inspired by [Dear ImGui](https://github.com/ocornut/imgui) and [ratatui's immediate-mode philosophy](https://ratatui.rs/concepts/backends/), but with Nu user controlling the main loop:

```nu
# Initialize terminal and enter raw mode
datatui init

# Application state - arbitrary Nu data structure
let mut state = {
  selected: 0
  items: (ls | select name size)
  filter: ""
  logs: []
}

# Main application loop - user controls everything
loop {
  # Get events from terminal (blocking until events available)
  let events = datatui events
  
  # Process events and update state
  $state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "j"} => {
        $acc | update selected (($acc.selected + 1) | math min (($acc.items | length) - 1))
      }
      {type: "key", key: "k"} => {
        $acc | update selected (($acc.selected - 1) | math max 0)
      }
      {type: "key", key: "enter"} => {
        let selected_item = $acc.items | get $acc.selected
        if $selected_item.type == "file" {
          $acc | update logs (open $selected_item.name | lines | first 10)
        } else { $acc }
      }
      {type: "key", key: "q"} => {
        break  # User decides when to exit
      }
      _ => $acc  # Ignore unhandled events
    }
  }
  
  # Create widgets using commands (not records)
  let file_list = datatui list --items ($state.items | get name) --selected $state.selected
  let preview = datatui text --content ($state.logs | str join "\n")
  
  # Render UI layout with widgets
  {
    layout: horizontal
    panes: [
      {widget: $file_list, size: "30%"}
      {widget: $preview, size: "70%"}
    ]
  } | datatui render
}

# Clean up terminal and restore normal mode
datatui terminate
```

### Why This Works

1. **User-Controlled Loop**: Like traditional ratatui apps, user controls when to exit, render, handle events
2. **Global Event Model**: Events are crossterm terminal events, not widget-specific - matches ratatui exactly
3. **Functional State Management**: Nu handles state transformations with immutable updates
4. **Command-Based Widgets**: All widgets created via commands for discoverability and consistency
5. **Composable**: Can integrate with other Nu operations, timers, external processes
6. **Nu-Native**: Leverages Nu's pattern matching, data transformation, and error handling

### Performance Characteristics

- **Complete re-rendering is optimal** for [ratatui's immediate-mode design](https://ratatui.rs/concepts/application-patterns/)
- **Widget state** (scroll positions, etc.) maintained by ratatui's [StatefulWidget system](https://docs.rs/ratatui/latest/ratatui/widgets/trait.StatefulWidget.html)
- **Layout cache** and terminal buffer optimizations handled by ratatui automatically
- **Event processing**: O(n) where n = events per frame (typically small)
- **Scope**: Small, focused applications with modest state sizes (< 10k items)

## Plugin API Design

### Core Commands

```nu
# Terminal lifecycle management
datatui init                    # Initialize terminal, enter raw mode, setup
datatui terminate              # Restore terminal, cleanup, exit

# Event handling
datatui events                 # Blocking call, returns all events since last call
datatui events --timeout 100ms # Non-blocking with timeout, returns events or empty list

# Widget creation commands (return widget references)
let file_list = datatui list --items $items --selected $cursor --scrollable
let data_table = datatui table --columns [name status pid] --rows $table_data --sortable
let preview = datatui text --content $text_content --scrollable --wrap
let search_box = datatui textarea --placeholder "Search..." --value $current_text

# Streaming widgets
let log_stream = datatui stream {|| tail -f /var/log/app.log}  # Create stream
let log_viewer = datatui streaming-text --stream $log_stream --auto-scroll
let proc_table = datatui streaming-table --stream $process_stream --refresh-rate "2sec"

# Layout and rendering
{
  layout: {
    direction: horizontal  # or vertical
    panes: [
      {widget: $file_list, size: "30%"}
      {widget: $preview, size: "*"}    # fill remaining
      {widget: $search_box, size: 3}   # fixed size
    ]
  }
} | datatui render

# Alternative single-widget rendering
$file_list | datatui render
```

### Event System

Events are global crossterm events returned by `datatui events`:

```nu
# Example events returned by datatui events
let events = [
  {type: "key", key: "j", modifiers: [], timestamp: (date now)}
  {type: "key", key: "Enter", modifiers: [], timestamp: (date now)}
  {type: "key", key: "q", modifiers: ["Ctrl"], timestamp: (date now)}
  {type: "mouse", x: 25, y: 10, button: "left", timestamp: (date now)}
  {type: "resize", width: 120, height: 30, timestamp: (date now)}
  {type: "paste", text: "pasted content", timestamp: (date now)}
]

# User processes events in main loop using Nu's pattern matching
loop {
  let events = datatui events
  
  $state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "q"} => break  # User controls exit
      {type: "key", key: "j"} => {
        $acc | update cursor (($acc.cursor + 1) | math min (($acc.items | length) - 1))
      }
      {type: "key", key: "Enter"} => {
        # Process selection...
        $acc | update selected_item ($acc.items | get $acc.cursor)
      }
      {type: "resize", width: $w, height: $h} => {
        $acc | update terminal {width: $w, height: $h}
      }
      _ => $acc # Ignore unhandled events
    }
  }
  
  
  # Create widgets and render
  let file_list = datatui list --items ($state.items | get name) --selected $state.cursor
  {layout: {panes: [{widget: $file_list}]}} | datatui render
}
```

### Widget Configuration

Widgets are pure data descriptions returned by the render function:

```nu
# List widget configuration
{
  type: "list"
  id: "file_browser"      # Required for event targeting
  items: ($files | get name)
  selected: $state.cursor
  highlight_style: "reverse"
  scrollable: true
  border: true
  title: "Files"
}

# Table widget configuration
{
  type: "table"
  id: "process_table"
  columns: [{name: "PID", width: 8}, {name: "Name", width: "*"}, {name: "CPU", width: 6}]
  rows: ($processes | each {|p| [$p.pid $p.name $"($p.cpu)%"]})
  selected: $state.selected_process
  sortable: true
  headers: true
}

# Layout configuration  
{
  layout: {
    direction: "horizontal"
    panes: [
      {widget: $list_widget, size: "30%"}
      {widget: $preview_widget, size: "*"}
      {widget: $status_widget, size: 20}  # Fixed size
    ]
  }
}
```

### Streaming Data (Phase 2)

For real-time data streams (logs, process output, file changes), datatui uses a functional stream management approach:

```nu
# 1. Create streams - execute closures once, return StreamId
let app_log = datatui stream {|| tail -f /var/log/app.log}
let error_log = datatui stream {|| tail -f /var/log/error.log}
let process_list = datatui stream {|| ps | select pid name cpu | to json}

# 2. Store StreamIds in state (not the data itself)
let initial_state = {
  streams: {
    app_log: $app_log
    error_log: $error_log
    processes: $process_list
  }
  log_scroll: 0
  selected_tab: 0
}

# 3. Use streams in user-controlled loop
datatui init

loop {
  let events = datatui events
  
  # Process events and update state
  $state = $events | reduce --fold $state {|event, acc|
    # ... event processing ...
  }
  
  # Create streaming widgets using commands
  let log_viewer = datatui streaming-text
    --stream $state.streams.app_log
    --scroll-position $state.log_scroll
    --auto-scroll
  
  let process_table = datatui streaming-table
    --stream $state.streams.processes
    --columns ["pid", "name", "cpu"]
    --refresh-rate "2sec"
  
  # Render layout
  {
    layout: {
      direction: horizontal
      panes: [
        {widget: $log_viewer, size: "70%"}
        {widget: $process_table, size: "30%"}
      ]
    }
  } | datatui render
}

datatui terminate

# 4. To refresh data: create new stream, old one gets GC'd
let refreshed_processes = datatui stream {|| ps | select pid name cpu mem | to json}
$state | update streams.processes $refreshed_processes
```

**Key Benefits:**
- **Functional**: Streams are immutable references, refresh by replacement
- **Automatic Cleanup**: Nu's GC calls `drop_notification()` on old StreamIds
- **No Side Effects**: Closures only executed on explicit `datatui stream` calls
- **Memory Efficient**: Plugin manages data internally, state only holds references
- **Scalable**: Works with any size dataset (logs, metrics, large tables)

## Implementation Plan

### Phase 1: Core Infrastructure
- [ ] Basic Nushell plugin setup with JSON-RPC
- [ ] Terminal initialization/cleanup
- [ ] Event loop with keyboard input
- [ ] State management (serialize/deserialize between Nu and Rust)
- [ ] Simple text widget for testing

### Phase 2: Basic Widgets
- [ ] List widget with selection
- [ ] Text display widget (scrollable, wrappable)
- [ ] Basic layout management (horizontal/vertical splits)
- [ ] Essential keybinding system

### Phase 3: Advanced Features
- [ ] Table widget with column management
- [ ] Menu widget (horizontal/vertical)
- [ ] Advanced layout (resizable panes, tabs)
- [ ] Styling and theming support

### Phase 4: Polish & Integration
- [ ] Performance optimization
- [ ] Error handling and recovery
- [ ] Documentation and examples
- [ ] Integration testing with jjiles and nucess

## Technical Challenges

### Plugin Communication
- **Challenge**: Nu plugins use JSON-RPC over stdin/stdout
- **Solution**: Efficient serialization of state and UI descriptions
- **Consideration**: Large datasets might need streaming or chunking

### Terminal State Management
- **Challenge**: Coordinate between Nu script execution and terminal UI
- **Solution**: Plugin handles all terminal operations, Nu only provides data/logic

### Event Loop Integration
- **Challenge**: Blocking event loop in plugin while maintaining Nu responsiveness
- **Solution**: Plugin runs its own event loop, calls back to Nu for state updates

### Widget State Synchronization
- **Challenge**: Ratatui widgets maintain internal state (scroll positions)
- **Solution**: Let ratatui handle widget state, only expose logical application state

## Success Criteria

1. **jjiles migration**: Successfully replace fzf-based jjiles with datatui version
2. **nucess completion**: Build functional process manager using datatui
3. **Performance**: Smooth interaction on reasonably-sized datasets (< 10k items)
4. **Usability**: Nu developers can build simple TUIs without deep ratatui knowledge
5. **Maintainability**: Clean separation between plugin (TUI) and Nu (logic) code

## References

### Core Technologies
- **[Ratatui Documentation](https://ratatui.rs/)**: Immediate-mode rendering, [state patterns](https://ratatui.rs/concepts/application-patterns/), [widget system](https://docs.rs/ratatui/latest/ratatui/widgets/)
- **[Nushell Plugin Guide](https://www.nushell.sh/contributor-book/plugins.html)**: Plugin development with [`nu-plugin` crate](https://docs.rs/nu-plugin/latest/nu_plugin/)
- **[Dear ImGui FAQ](https://github.com/ocornut/imgui/blob/master/docs/FAQ.md#q-what-is-immediate-mode-gui-dear-imgui)**: Immediate-mode GUI philosophy and patterns

### Implementation References  
- **jjiles codebase**: Complex TUI requirements, streaming data, multi-view navigation
- **nucess requirements**: Multi-pane layouts, process management, real-time updates  
- **[Nu-plugin examples](https://github.com/nushell/nushell/tree/main/crates/nu_plugin_example)**: Reference plugin implementation
- **[Ratatui examples](https://github.com/ratatui/ratatui/tree/main/examples)**: Widget usage patterns and state management

### Related Projects
- **[nu_plugin_explore](https://github.com/nushell/nushell/tree/main/crates/nu-explore)**: Nushell's built-in TUI explorer using ratatui
- **[Crossterm](https://docs.rs/crossterm/latest/crossterm/)**: Cross-platform terminal manipulation library

## Future Evolution

### Potential Extensions
- **Mouse support**: If needed for specific applications
- **Advanced widgets**: Trees, graphs, charts
- **Plugin ecosystem**: Community-contributed widget types
- **Cross-platform**: Ensure Windows/Mac/Linux compatibility

### Alternative Approaches
If the plugin model proves limiting:
- **Standalone binary**: Like current jjiles approach, but purpose-built
- **Nu built-in**: Integration directly into Nushell core (long-term possibility)