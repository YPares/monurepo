# datatui Implementation Roadmap

## 🎉 CURRENT STATUS SUMMARY

### ✅ **COMPLETED (MVP Foundation + Layout System)**
We have successfully implemented the core foundation:
- Basic Nushell plugin structure with proper nu-plugin integration
- **Session-based Terminal management** with efficient reuse (improved from re-creation issue)
- Event collection system (keyboard, mouse, resize, paste events)
- Basic widget system (text and list widgets)
- Widget storage and custom value references
- Single widget rendering
- **✨ MULTI-WIDGET LAYOUT SYSTEM** - Horizontal/vertical layouts with percentage, fixed, and fill sizing
- Plugin registration and command discovery

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

---

## Phase 1: Foundation (MVP) ✨ Priority

### Core Infrastructure
- [x] **Nushell Plugin Setup**
  - [x] Create Cargo workspace with plugin crate
  - [x] Implement Plugin and SimplePluginCommand traits (nu-plugin handles JSON-RPC automatically!)
  - [x] Set up Nu plugin registration and discovery
  - [x] Handle plugin lifecycle (init, run, cleanup)

- [x] **Terminal Management**
  - [x] Terminal initialization with crossterm backend
  - [x] **Session-based Terminal reuse** - Efficient Terminal instance management
  - [x] Alternate screen mode handling
  - [x] Raw mode setup/cleanup
  - [x] Terminal lifecycle control (init → reuse → terminate)
  - [ ] Proper cleanup on exit/panic  # TODO: Add panic handlers and signal handling
  - [ ] Signal handling (SIGINT, SIGTERM)  # TODO: Implement graceful shutdown on signals

- [x] **Command Structure**
  - [x] `datatui init` - terminal initialization
  - [x] `datatui events` - crossterm event collection
  - [x] `datatui render` - layout rendering (single widget only)
  - [x] `datatui terminate` - terminal cleanup
  - [x] Error handling and recovery

- [x] **Widget Command System**
  - [x] `datatui text` - text widget creation
  - [x] `datatui list` - list widget creation
  - [x] Widget storage (HashMap<WidgetId, Widget>)
  - [x] Widget reference custom values (WidgetRef)
  - [x] **Multi-widget layout system** - Complete layout rendering with multiple widgets

### Milestone: "Hello World" TUI ✅ COMPLETED
```nu
datatui init
let text_widget = datatui text --content "Hello World!"
$text_widget | datatui render
datatui terminate
```

## Phase 2: Core Widgets 📦

### Essential Widgets
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

- [x] **Layout System** ✅ COMPLETED - Major milestone achieved!
  - [x] Horizontal/vertical splits - Parse layout records from Nu
  - [x] Percentage and fixed sizing - Support "30%", "*", and fixed numbers
  - [x] Multi-widget rendering - Render layout with multiple WidgetRefs
  - [x] Size constraint conversion - Nu values → ratatui constraints
  - [ ] Nested layouts  # TODO: Allow layouts within layouts (future enhancement)
  - [ ] Dynamic layout recalculation  # TODO: Recalculate on terminal resize

### Milestone: File Browser ✅ READY TO IMPLEMENT
Basic file browser with list + preview pane (see EXAMPLES.md) - Layout system complete!

## Phase 3: Advanced Widgets 🚀  # TODO: Next major phase after Phase 2 layout system

### Enhanced Widgets
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
  - [ ] Text input field
  - [ ] Multi-line text area
  - [ ] Input validation
  - [ ] Form-like widget composition

### Milestone: Process Manager (nucess)
Multi-pane process management interface (see EXAMPLES.md)

## Phase 3.5: Streaming Data (🌊 Major Architectural Feature)

### Streaming Data System  # TODO: Critical for real-time applications like nucess
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

## Phase 4: Advanced Features ⚡

### Performance & Polish
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

## Phase 5: Integration & Polish 🎯

### jjiles Migration
- [ ] **Analysis**
  - [ ] Identify fzf replacement requirements
  - [ ] Map current keybindings to datatui events
  - [ ] Plan streaming data integration
  - [ ] Performance benchmarking requirements

- [ ] **Implementation**
  - [ ] Replace fzf calls with datatui
  - [ ] Implement multi-view navigation (OpLog → RevLog → EvoLog → Files)
  - [ ] Preserve all existing functionality
  - [ ] Maintain or improve performance

- [ ] **Testing**
  - [ ] Feature parity validation
  - [ ] Performance comparison with fzf version
  - [ ] User acceptance testing
  - [ ] Edge case handling

### Documentation & Examples
- [ ] **User Guide**
  - [ ] Getting started tutorial
  - [ ] Widget reference documentation
  - [ ] Event handling patterns
  - [ ] State management best practices

- [ ] **Developer Documentation**
  - [ ] Plugin architecture explanation
  - [ ] Contributing guidelines
  - [ ] Widget development guide
  - [ ] Performance optimization tips

## Technical Debt & Maintenance

### Code Quality
- [ ] **Testing**
  - [ ] Unit tests for all widgets
  - [ ] Integration tests for event system
  - [ ] Nu script testing framework
  - [ ] Performance benchmarks

- [ ] **CI/CD**
  - [ ] GitHub Actions setup
  - [ ] Automated testing
  - [ ] Release automation
  - [ ] Cross-platform builds

- [ ] **Error Handling**
  - [ ] Comprehensive error messages
  - [ ] Graceful degradation
  - [ ] Recovery mechanisms
  - [ ] Debug mode/logging

## Future Enhancements (Post-MVP)

### Community Features
- [ ] **Widget Ecosystem**
  - [ ] Plugin API for custom widgets
  - [ ] Community widget registry
  - [ ] Widget composition patterns
  - [ ] Reusable component library

- [ ] **Platform Support**
  - [ ] Windows compatibility testing
  - [ ] macOS compatibility testing
  - [ ] Different terminal emulator support
  - [ ] Alternative backend support

### Advanced Use Cases
- [ ] **Specialized Widgets**
  - [ ] Chart/graph widgets
  - [ ] Tree view widget
  - [ ] Progress bars and gauges
  - [ ] Image display (if feasible)

- [ ] **Integration Options**
  - [ ] Export to other TUI frameworks
  - [ ] Web-based rendering option
  - [ ] Screen recording/replay
  - [ ] Remote TUI access

## Risk Mitigation

### High-Risk Items
- [ ] **Performance Bottlenecks**
  - Risk: Large datasets causing UI lag
  - Mitigation: Virtual scrolling, efficient rendering, benchmarking
  
- [ ] **Nu Plugin Stability**
  - Risk: Plugin crashes affecting Nu shell
  - Mitigation: Robust error handling, process isolation, recovery

- [ ] **Platform Compatibility**
  - Risk: Terminal differences across platforms
  - Mitigation: Comprehensive testing, fallback options

### Success Metrics
- [ ] **Functional Metrics**
  - jjiles feature parity achieved
  - nucess MVP completed
  - Performance within 10% of fzf-based jjiles

- [ ] **Quality Metrics**
  - <1% crash rate in normal usage
  - Memory usage stable over time
  - Startup time <100ms for typical use cases

- [ ] **Adoption Metrics**
  - Successful migration of existing jjiles users
  - Community interest in building new datatui applications
  - Documentation completeness (>90% coverage)

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