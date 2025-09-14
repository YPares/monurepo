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

### Events-in-Render Model (True Immediate Mode)

Inspired by [Dear ImGui](https://github.com/ocornut/imgui) and [ratatui's immediate-mode philosophy](https://ratatui.rs/concepts/backends/), where events are processed during rendering:

```nu
# Application state - arbitrary Nu data structure
let state = {
  selected: 0
  items: (ls | select name size)
  filter: ""
  logs: []
}

# Pure render function: (state, events) -> {state: new_state, ui: ui_description}
let render = {|state, events|
  # Process ALL events first, producing new state
  let new_state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "j", widget_id: "file_list"} => {
        $acc | update selected (($acc.selected + 1) | math min (($acc.items | length) - 1))
      }
      {type: "key", key: "k", widget_id: "file_list"} => {
        $acc | update selected (($acc.selected - 1) | math max 0)
      }
      {type: "key", key: "enter", widget_id: "file_list"} => {
        let selected_item = $acc.items | get $acc.selected
        if $selected_item.type == "file" {
          $acc | update logs (open $selected_item.name | lines | first 10)
        } else { $acc }
      }
      {type: "select", index: $idx, widget_id: "file_list"} => {
        $acc | update selected $idx
      }
      _ => $acc  # Ignore unhandled events
    }
  }
  
  # Then describe UI based on new state
  {
    state: $new_state
    ui: {
      layout: horizontal
      panes: [
        {
          widget: {
            type: "list"
            id: "file_list"  # Widget ID for event targeting
            items: ($new_state.items | get name)
            selected: $new_state.selected
          }
          size: "30%"
        }
        {
          widget: {
            type: "text"
            content: ($new_state.logs | str join "\n")
          }
          size: "70%"  
        }
      ]
    }
  }
}

# Plugin runs the immediate-mode loop
datatui run --state $state --render $render
```

### Why This Works

1. **True Immediate Mode**: Events processed during rendering, just like [Dear ImGui](https://github.com/ocornut/imgui/blob/master/docs/FAQ.md#q-what-is-immediate-mode-gui-dear-imgui)
2. **No Event Routing**: Render function sees all events and decides what to do
3. **Functional Purity**: `(state, events) → (new_state, ui_description)` - pure function
4. **Widget Focus Automatic**: Events include `widget_id` so render function knows context
5. **Nu-Native**: Leverages Nu's pattern matching and data transformation pipelines

### Performance Characteristics

- **Complete re-rendering is optimal** for [ratatui's immediate-mode design](https://ratatui.rs/concepts/application-patterns/)
- **Widget state** (scroll positions, etc.) maintained by ratatui's [StatefulWidget system](https://docs.rs/ratatui/latest/ratatui/widgets/trait.StatefulWidget.html)
- **Layout cache** and terminal buffer optimizations handled by ratatui automatically
- **Event processing**: O(n) where n = events per frame (typically small)
- **Scope**: Small, focused applications with modest state sizes (< 10k items)

## Plugin API Design

### Core Commands

```nu
# Main immediate-mode loop - render function handles everything
datatui run --state $initial_state --render $render_closure

# Widget descriptions (no callbacks - pure data)
{
  type: "list"
  id: "main_list"       # Required for event targeting
  items: $data
  selected: $idx
  scrollable: true
}

{
  type: "table" 
  id: "data_table"
  columns: [name status pid]
  rows: $table_data
  sortable: true
}

{
  type: "text"
  content: $text_content
  scrollable: true
  wrap: true
}

# Layout descriptions
{
  layout: {
    direction: horizontal  # or vertical
    panes: [
      {widget: $widget1, size: "30%"}
      {widget: $widget2, size: "*"}    # fill remaining
      {widget: $widget3, size: 20}     # fixed size
    ]
  }
}
```

### Event System

Events are included in the render call as structured data:

```nu
# Example events passed to render function
let events = [
  {type: "key", key: "j", widget_id: "main_list", timestamp: (date now)}
  {type: "key", key: "enter", widget_id: "main_list", timestamp: (date now)}
  {type: "select", index: 5, widget_id: "main_list", timestamp: (date now)}
  {type: "resize", width: 120, height: 30, timestamp: (date now)}
  {type: "focus", widget_id: "search_box", timestamp: (date now)}
]

# The render function processes these events using Nu's pattern matching
let render = {|state, events|
  let new_state = $events | reduce --fold $state {|event, acc|
    match $event {
      {type: "key", key: "q"} => (exit) # Global quit
      {type: "key", key: "j", widget_id: "main_list"} => {
        $acc | update cursor (($acc.cursor + 1) | math min (($acc.items | length) - 1))
      }
      {type: "resize", width: $w, height: $h} => {
        $acc | update terminal {width: $w, height: $h}
      }
      _ => $acc # Ignore unhandled events
    }
  }
  
  {state: $new_state, ui: (build-ui $new_state)}
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