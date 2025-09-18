# datatui: Nushell Ratatui Plugin

## Vision & Philosophy

`datatui` is a low-level Nushell plugin that bridges Nu's data-centric world with terminal user interfaces. It provides primitive TUI widgets and layout management, allowing Nu scripts to build interactive applications using a reactive, state-driven architecture.

**Core Philosophy**: Keep the plugin simple and generic. Application logic stays in Nushell, datatui only handles TUI rendering and event dispatch.

## Use Cases

### Confirmed Applications
1. **jjiles**: Interactive revision browser for Jujutsu version control
   - Multi-view navigation (OpLog → RevLog → EvoLog → Files)
   - Streaming content with real-time updates
   - Complex keybinding system

2. **nucess**: Process management TUI (Nushell version of mprocs)
   - Multi-pane layout for process logs
   - Process control (start/stop/restart)
   - Real-time log streaming

### Future Potential
- File explorers, System monitors, Interactive data viewers, Configuration UIs

## 🎉 CURRENT STATUS

### ✅ **COMPLETED (MVP + Layout System)**
Core foundation complete with major Layout System milestone:
- Complete Nushell plugin with session-based Terminal management
- Multi-widget layout system (horizontal/vertical, percentage/fixed/fill sizing)
- Widget storage with automatic garbage collection
- Event collection system (keyboard, mouse, resize, paste)
- Text and List widgets with basic functionality

### 🚧 **HIGH PRIORITY TODO (Phase 2)**
Critical features needed for practical applications:

1. **StatefulWidget Integration** - For proper scrolling and selection within widgets
2. **Table Widget** - Essential for jjiles and nucess
3. **Interactive Event Loop Support** - Navigation within widgets
4. **Streaming Data System** - For real-time updates

### 📋 **MEDIUM PRIORITY TODO (Phase 3+)**
Features for advanced applications:
- Streaming data widgets (datatui stream command)
- Advanced styling and theming
- Performance optimizations
- Additional widget types (menu, input, etc.)

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

  # Process events and update state (pure Nu logic)
  $state = ($events | reduce --fold $state {|event, acc|
    match $event.type {
      "key" => {
        if $event.key == "j" {
          $acc | update selected {|s| $s + 1}
        } else if $event.key == "k" {
          $acc | update selected {|s| $s - 1}
        } else { $acc }
      }
      _ => $acc
    }
  })

  # Create widgets based on current state
  let file_list = datatui list --items $state.items --selected $state.selected
  let preview = datatui text --content (open ($state.items | get $state.selected).name)

  # Render layout with widgets
  {
    layout: {
      direction: "horizontal"
      panes: [
        {widget: $file_list, size: "30%"}
        {widget: $preview, size: "*"}
      ]
    }
  } | datatui render

  # Exit condition
  if ($events | any {|e| $e.key == "q"}) { break }
}

# Clean up terminal
datatui terminate
```

### Widget Configuration Format

```nu
# Text widget configuration
{
  type: "text"
  id: "status_bar"
  content: "Ready"
  wrap: true
  scroll: 0
  border: true
  title: "Status"
}

# List widget configuration
{
  type: "list"
  id: "file_browser"
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
  selected_process: 0
}

# 3. Use streams in widgets - data fetched by plugin automatically
let log_widget = datatui streaming-text --stream $state.streams.app_log --title "Application Log"
let process_widget = datatui streaming-table --stream $state.streams.processes --title "Processes"

# 4. Streams cleaned up automatically when StreamIds dropped or explicit cleanup
$state.streams.app_log | datatui stream-close  # Manual cleanup if needed
```

**Key principles:**
- **Pure Functions**: Closures execute independently, return data without side effects
- **No Side Effects**: Closures only executed on explicit `datatui stream` calls
- **Memory Efficient**: Plugin manages data internally, state only holds references
- **Scalable**: Works with any size dataset (logs, metrics, large tables)

## Detailed Implementation Roadmap

### Phase 1: Foundation (MVP) ✅ COMPLETED

#### Core Infrastructure
- [x] **Nushell Plugin Setup**
  - [x] Create Cargo workspace with plugin crate
  - [x] Implement Plugin and SimplePluginCommand traits (nu-plugin handles JSON-RPC automatically!)
  - [x] Set up Nu plugin registration and discovery
  - [x] Handle plugin lifecycle (init, run, cleanup)

- [x] **Terminal Management** - Session-based with init → reuse → terminate lifecycle
  - [ ] Panic handlers and signal handling  # TODO: Graceful shutdown improvements

- [x] **Command Structure**
  - [x] `datatui init` - terminal initialization
  - [x] `datatui events` - crossterm event collection
  - [x] `datatui render` - layout rendering (single widget only)
  - [x] `datatui terminate` - terminal cleanup
  - [x] Error handling and recovery

- [x] **Widget & Layout System** - Complete with automatic garbage collection

### Milestone: "Hello World" TUI ✅ COMPLETED
```nu
datatui init
let text_widget = datatui text --content "Hello World!"
$text_widget | datatui render
datatui terminate
```

### Phase 2: Core Widgets 📦

#### Essential Widgets
- [x] **List Widget** (Basic implementation)
  - [x] Basic list rendering
  - [x] Selection/highlighting (basic support)
  - [ ] Scroll state management  # TODO: Implement proper StatefulWidget scrolling
  - [x] Item formatting from Nu data
  - [ ] Keyboard navigation (j/k, arrows)  # TODO: Add interactive keyboard navigation

- [x] **Text Widget Enhancement** (Basic implementation)
  - [ ] Scrollable text content  # TODO: Implement text scrolling with StatefulWidget
  - [x] Line wrapping support
  - [ ] Basic styling (bold, colors)  # TODO: Add text styling options
  - [ ] Search within text  # TODO: Add text search functionality

### Milestone: File Browser ✅ READY TO IMPLEMENT
Layout system enables file browser with list + preview pane (see EXAMPLES.md)

### Phase 3: Advanced Widgets 🚀

#### Enhanced Widgets
- [ ] **Table Widget**  # TODO: High priority for nucess and jjiles
  - [ ] Column-based data display
  - [ ] Column headers and sizing
  - [ ] Row selection
  - [ ] Basic sorting capability
  - [ ] Column alignment

- [ ] **Menu Widget**  # TODO: Medium priority
  - [ ] Horizontal/vertical menu bars
  - [ ] Submenu support
  - [ ] Menu item callbacks
  - [ ] Keyboard shortcuts display

- [ ] **Input Widgets**  # TODO: Medium priority for interactive applications
  - [ ] Text input field ( with https://github.com/rhysd/tui-textarea )
  - [ ] Multi-line text area ( also with https://github.com/rhysd/tui-textarea )
  - [ ] Input validation
  - [ ] Form-like widget composition

### Milestone: Process Manager (nucess)
Multi-pane process management interface (see EXAMPLES.md)

### Phase 3.5: Streaming Data (🌊 Major Architectural Feature)

#### Streaming Data System  # TODO: Critical for real-time applications like nucess
- [ ] **Stream Command**  # `datatui stream {|| command}` - execute closures and return StreamId
  - [ ] StreamId custom value type
  - [ ] Closure execution and data capture
  - [ ] Automatic cleanup on StreamId drop
  - [ ] Stream refresh by replacement

- [ ] **Streaming Widgets**  # Widgets that consume live data streams
  - [ ] `datatui streaming-text` - Live log viewer with auto-scroll
  - [ ] `datatui streaming-table` - Live data table with refresh rates
  - [ ] Stream integration with existing widgets
  - [ ] Buffer management and memory limits

- [ ] **Stream Management**  # Handle multiple concurrent streams
  - [ ] Stream lifecycle management
  - [ ] Memory-efficient streaming
  - [ ] Stream error handling and recovery
  - [ ] Rate limiting and backpressure

### Phase 4: Advanced Features ⚡

#### Performance & Polish
- [ ] **Optimization**  # TODO: Important for large datasets in jjiles
  - [ ] Efficient state diff detection
  - [ ] Widget render caching
  - [ ] Large dataset handling (virtual scrolling)  # Critical for jjiles with many commits
  - [ ] Memory usage optimization

- [ ] **Advanced Event System**  # TODO: Enhance interactivity
  - [ ] Mouse support (optional)  # Nice-to-have for clicking and scrolling
  - [ ] Timer/interval events  # For auto-refresh and animations
  - [ ] Custom event types
  - [ ] Event batching/debouncing

- [ ] **Styling System**  # TODO: Medium priority for polish
  - [ ] Theme support
  - [ ] Color schemes
  - [ ] Border styles
  - [ ] Custom widget styling

- [ ] **Error Handling & Robustness**  # TODO: Critical for production use
  - [ ] Panic handlers with terminal cleanup  # Prevent terminal corruption
  - [ ] Signal handling (SIGINT, SIGTERM)  # Graceful shutdown
  - [ ] Plugin crash recovery  # Don't crash Nu shell
  - [ ] Better error messages with context

### Milestone: Real-time Monitor
Live updating dashboard with multiple data sources (see EXAMPLES.md)

## Technical Challenges

### Terminal State Management
**Challenge**: Ensuring terminal state is properly managed across plugin invocations
**Solution**: Session-based Terminal storage with proper lifecycle management

### Widget Lifetime Management
**Challenge**: Widgets created in Nu must be accessible across multiple render calls
**Solution**: Widget storage in plugin with automatic garbage collection via custom_value_dropped

### Event Loop Integration
**Challenge**: Nu scripts need to control the main loop while plugin handles terminal events
**Solution**: `datatui events` command provides blocking event collection, Nu script processes them

### Performance with Large Datasets
**Challenge**: Rendering large tables or logs without UI lag
**Solution**: Virtual scrolling, efficient rendering, and streaming data architecture

## Development Notes

### Key Dependencies
- **ratatui**: Core TUI framework (~0.30+)
- **crossterm**: Terminal backend (latest stable)
- **serde**: JSON serialization for Nu communication
- **tokio**: Async runtime if needed for events
- **nu-plugin**: Nushell plugin framework

### Development Environment
- **Minimum Rust Version**: 1.70+ (for latest ratatui features)
- **Testing**: Requires Nu shell installed for integration tests
- **Platforms**: Primary development on Linux, with Windows/macOS CI testing

### Communication Protocol
- **Nu ↔ Plugin**: JSON-RPC over stdin/stdout (handled by nu-plugin crate)
- **Widget Creation**: Command parameters → Widget storage + WidgetRef return
- **Event Flow**: Plugin collects crossterm events → Nu processes in loop
- **Rendering**: Nu sends layout with WidgetRefs → Plugin renders via ratatui
- **Error Handling**: Structured error responses with context

This roadmap provides a clear path from basic functionality to full feature parity with existing tools, while maintaining focus on the core value proposition of bridging Nu's data manipulation capabilities with rich terminal UIs.
