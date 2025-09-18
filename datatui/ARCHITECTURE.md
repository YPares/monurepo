# datatui Architecture Deep Dive

## Plugin Architecture Overview

```
┌─────────────────┐    JSON-RPC     ┌──────────────────┐
│   Nushell       │◄────────────────┤   datatui        │
│   Script        │                 │   Plugin         │
│                 │                 │                  │
│ • State mgmt    │                 │ • Terminal       │
│ • Event logic   │    State +      │   control        │
│ • Data proc.    │    UI Desc      │ • Ratatui        │
│ • Closures      │────────────────►│   rendering      │
└─────────────────┘                 │ • Event loop     │
                                    └──────────────────┘
```

## State Flow Cycle (User-Controlled Loop)

```
  ┌─────────────────────────────────────────────────────┐
  │                 Nu Script                           │
  │                                                     │
  │  1. datatui init (setup terminal)                   │
  │  2. loop {                                          │
  │       let events = datatui events  # Get events     │
  │       $state = process_events($state, $events)      │
  │       let widgets = create_widgets($state)          │
  │       {layout: ...} | datatui render                │
  │     }                                               │
  │  3. datatui terminate (cleanup terminal)            │
  └─────────────────────────────────────────────────────┘
                          ↑                ↓
                     Events          Render commands
                          ↑                ↓
  ┌─────────────────────────────────────────────────────┐
  │               datatui Plugin                        │
  │                                                     │
  │  • Terminal management (init/terminate)             │
  │  • Event collection (crossterm::event::read)        │
  │  • Widget storage (HashMap<WidgetId, Widget>)       │
  │  • Rendering (ratatui draw calls)                   │
  │  • No application state - Nu manages everything     │
  └─────────────────────────────────────────────────────┘
```

## Data Structures

### State (Arbitrary Nu Record)
```nu
# Example application state - completely user-defined
{
  # UI state
  cursor: 5
  selected_view: "list"
  filter: "*.txt"
  
  # Application data  
  items: [
    {name: "file1.txt", size: 1024}
    {name: "file2.txt", size: 2048}
  ]
  
  # Dynamic content
  preview: "File contents here..."
  logs: ["Started", "Processing..."]
  
  # Computed values
  filtered_items: (computed from items + filter)
}
```

### Events List (Plugin → Nu)
```nu
# Events returned by datatui events - global crossterm events
[
  {
    type: "key"
    key: "j" 
    modifiers: []
    timestamp: 1234567890
  }
  {
    type: "key"
    key: "Enter"
    modifiers: []
    timestamp: 1234567891
  }
  {
    type: "key"
    key: "q"
    modifiers: ["Ctrl"]
    timestamp: 1234567892
  }
  {
    type: "mouse"
    x: 25
    y: 10 
    button: "left"
    timestamp: 1234567893
  }
  {
    type: "resize" 
    width: 120
    height: 30
    timestamp: 1234567894
  }
  {
    type: "paste"
    text: "pasted content"
    timestamp: 1234567895
  }
]
```

### Widget Commands and Layout (Nu → Plugin)
```nu
# Widget creation commands return widget references
let file_list = datatui list --items ["file1.txt", "file2.txt", "document.txt"] --selected 2
let preview = datatui text --content "Document contents here..." --wrap
let search_box = datatui textarea --placeholder "Search..."

# Layout structure sent to plugin via render command
{
  layout: {
    direction: horizontal
    panes: [
      {widget: $file_list, size: "30%"}
      {widget: $preview, size: "*"}
      {widget: $search_box, size: 3}
    ]
  }
} | datatui render
  # Create widgets using datatui commands
  let file_list = datatui list --items ["file1.txt", "file2.txt", "document.txt"] --selected 3 --title "Files"
  let preview = datatui text --content "Document contents here..." --title "Preview"

  # Layout with widgets
  {
    layout: {
      direction: "horizontal"
      panes: [
        {widget: $file_list, size: "30%"}
        {widget: $preview, size: "*"}
      ]
    }
  }
```

### Example Application Loop (Nu)
```nu
# Initialize terminal
datatui init

# Application state managed by Nu
let mut state = {
  cursor: 0
  items: (ls | select name type size)
  preview: ""
  terminal: {width: 80, height: 24}
}

# Main event loop - user controls everything
loop {
  # Get events from terminal
  let events = datatui events
  
  # Process events to update state
  $state = $events | reduce --fold $state {|event, acc|
    match $event {
      # Navigation events
      {type: "key", key: "j"} => {
        $acc | update cursor (($acc.cursor + 1) | math min (($acc.items | length) - 1))
      }
      {type: "key", key: "k"} => {
        $acc | update cursor (($acc.cursor - 1) | math max 0)
      }
      
      # Selection events
      {type: "key", key: "Enter"} => {
        let selected = $acc.items | get $acc.cursor
        if $selected.type == "file" {
          $acc | update preview (open $selected.name | str substring 0..1000)
        } else { $acc }
      }
      
      # Global events
      {type: "key", key: "q"} => break  # User controls exit
      {type: "resize", width: $w, height: $h} => {
        $acc | update terminal {width: $w, height: $h}
      }
      
      # Ignore unhandled events
      _ => $acc
    }
  }
  
  # Create widgets using commands
  let file_list = datatui list --items ($state.items | get name) --selected $state.cursor
  let preview_text = datatui text --content $state.preview --wrap
  
  # Render layout
  {
    layout: {
      direction: "horizontal"
      panes: [
        {widget: $file_list, size: "30%"}
        {widget: $preview_text, size: "*"}
      ]
    }
  } | datatui render
}

# Clean up terminal
datatui terminate
```

## Plugin Implementation Details

### Simple Plugin Structure (using nu-plugin crate)
```rust
use nu_plugin::{serve_plugin, Plugin, PluginCommand, SimplePluginCommand, MsgPackSerializer};
use nu_plugin::{EngineInterface, EvaluatedCall};
use nu_protocol::{LabeledError, Signature, Value, Type, Span, PipelineData};
use ratatui::{backend::CrosstermBackend, Terminal, Frame};
use crossterm::event::{self, Event, KeyEvent, KeyEventKind, MouseEvent};
use std::io::{self, Stdout};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::collections::HashMap;

struct Datatui {
    widgets: HashMap<WidgetId, Box<dyn ratatui::widgets::Widget>>,
    terminal: Option<Terminal<CrosstermBackend<Stdout>>>,
}

type WidgetId = u64;

// Custom value for widget references
#[derive(Debug, Clone)]
pub struct WidgetRef {
    pub id: WidgetId,
}

impl nu_protocol::CustomValue for WidgetRef {
    fn clone_value(&self, span: Span) -> Value {
        Value::custom(Box::new(self.clone()), span)
    }
    
    fn type_name(&self) -> String {
        "widget_ref".into()
    }
    
    fn to_base_value(&self, span: Span) -> Result<Value, nu_protocol::ShellError> {
        Ok(Value::string(format!("WidgetRef({})", self.id), span))
    }
    
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}
struct InitCommand;
struct EventsCommand;
struct RenderCommand;
struct TerminateCommand;
struct ListCommand;
struct TextCommand;

impl Plugin for Datatui {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![
            Box::new(InitCommand),
            Box::new(EventsCommand), 
            Box::new(RenderCommand),
            Box::new(TerminateCommand),
            Box::new(ListCommand),
            Box::new(TextCommand),
            // ... other widget commands
        ]
    }
}

// Example command implementations
impl SimplePluginCommand for InitCommand {
    type Plugin = Datatui;
    
    fn name(&self) -> &str { "datatui init" }
    fn description(&self) -> &str { "Initialize terminal for TUI mode" }
    
    fn run(&self, plugin: &Datatui, engine: &EngineInterface, 
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Initialize terminal, enter raw mode, setup crossterm
        let backend = CrosstermBackend::new(io::stdout());
        let terminal = Terminal::new(backend).map_err(|e| {
            LabeledError::new(format!("Failed to initialize terminal: {}", e))
        })?;
        
        // Enable raw mode and setup
        crossterm::terminal::enable_raw_mode().map_err(|e| {
            LabeledError::new(format!("Failed to enable raw mode: {}", e))
        })?;
        
        Ok(Value::nothing(call.head))
    }
}

impl SimplePluginCommand for EventsCommand {
    type Plugin = Datatui;
    
    fn name(&self) -> &str { "datatui events" }
    fn description(&self) -> &str { "Get terminal events (blocking)" }
    
    fn run(&self, plugin: &Datatui, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Call crossterm::event::read(), convert to Nu values
        let events = collect_crossterm_events().map_err(|e| {
            LabeledError::new(format!("Failed to read events: {}", e))
        })?;
        Ok(events_to_nu_values(events, call.head))
    }
}

impl SimplePluginCommand for ListCommand {
    type Plugin = Datatui;
    
    fn name(&self) -> &str { "datatui list" }
    fn description(&self) -> &str { "Create a list widget" }
    fn signature(&self) -> Signature {
        Signature::build("datatui list")
            .named("items", nu_protocol::SyntaxShape::List(Box::new(nu_protocol::SyntaxShape::Any)), "List items", None)
            .named("selected", nu_protocol::SyntaxShape::Int, "Selected index", None)
            .switch("scrollable", "Make list scrollable", None)
    }
    
    fn run(&self, plugin: &Datatui, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Create widget, store in plugin, return widget ID
        let widget_id = self.create_list_widget(plugin, call).map_err(|e| {
            LabeledError::new(format!("Failed to create list widget: {}", e))
        })?;
        Ok(Value::custom(Box::new(WidgetRef { id: widget_id }), call.head))
    }
}

fn main() {
    serve_plugin(&Datatui::default(), MsgPackSerializer);
}

impl Default for Datatui {
    fn default() -> Self {
        Self {
            widgets: HashMap::new(),
            terminal: None,
        }
    }
}

impl SimplePluginCommand for RenderCommand {
    type Plugin = Datatui;
    
    fn name(&self) -> &str { "datatui render" }
    fn description(&self) -> &str { "Render UI layout to terminal" }
    
    fn run(&self, plugin: &Datatui, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        let layout = input.as_record().map_err(|e| {
            LabeledError::new(format!("Invalid layout format: {}", e))
        })?;
        self.render_layout_to_terminal(plugin, layout).map_err(|e| {
            LabeledError::new(format!("Failed to render layout: {}", e))
        })?;
        Ok(Value::nothing(call.head))
    }
}

// Define event types for the plugin
#[derive(Debug, Clone)]
enum DatatuiEvent {
    Key(KeyEvent),
    Mouse(MouseEvent),
    Resize(u16, u16),
    Paste(String),
}

// Core event collection function
fn collect_crossterm_events() -> Result<Vec<DatatuiEvent>, crossterm::ErrorKind> {
    let mut events = Vec::new();
    
    // Block for first event, then collect all available events non-blocking
    match event::read() {
        Ok(first_event) => {
            match first_event {
                Event::Key(key_event) if key_event.kind == KeyEventKind::Press => {
                    events.push(DatatuiEvent::Key(key_event));
                }
                Event::Mouse(mouse_event) => {
                    events.push(DatatuiEvent::Mouse(mouse_event));
                }
                Event::Resize(w, h) => {
                    events.push(DatatuiEvent::Resize(w, h));
                }
                Event::Paste(text) => {
                    events.push(DatatuiEvent::Paste(text));
                }
                _ => {} // Ignore other events
            }
            
            // Collect any additional events available immediately
            while event::poll(Duration::from_millis(0))? {
                match event::read()? {
                    Event::Key(key_event) if key_event.kind == KeyEventKind::Press => {
                        events.push(DatatuiEvent::Key(key_event));
                    }
                    Event::Mouse(mouse_event) => {
                        events.push(DatatuiEvent::Mouse(mouse_event));
                    }
                    Event::Resize(w, h) => {
                        events.push(DatatuiEvent::Resize(w, h));
                    }
                    Event::Paste(text) => {
                        events.push(DatatuiEvent::Paste(text));
                    }
                    _ => {} // Ignore other events
                }
            }
        }
        Err(e) => return Err(e),
    }
    
    Ok(events)
}

// Convert crossterm events to Nu values using modern API
fn events_to_nu_values(events: Vec<DatatuiEvent>, span: Span) -> Value {
    let nu_events = events.into_iter().map(|event| {
        match event {
            DatatuiEvent::Key(key_event) => {
                Value::record(
                    vec![
                        ("type".into(), Value::string("key", span)),
                        ("key".into(), Value::string(format!("{:?}", key_event.code), span)),
                        ("modifiers".into(), Value::list(format_modifiers(key_event.modifiers, span), span)),
                        ("timestamp".into(), Value::int(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64, span)),
                    ],
                    span,
                )
            }
            DatatuiEvent::Mouse(mouse_event) => {
                Value::record(
                    vec![
                        ("type".into(), Value::string("mouse", span)),
                        ("x".into(), Value::int(mouse_event.column as i64, span)),
                        ("y".into(), Value::int(mouse_event.row as i64, span)),
                        ("button".into(), Value::string(format!("{:?}", mouse_event.kind), span)),
                        ("timestamp".into(), Value::int(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64, span)),
                    ],
                    span,
                )
            }
            DatatuiEvent::Resize(w, h) => {
                Value::record(
                    vec![
                        ("type".into(), Value::string("resize", span)),
                        ("width".into(), Value::int(w as i64, span)),
                        ("height".into(), Value::int(h as i64, span)),
                        ("timestamp".into(), Value::int(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64, span)),
                    ],
                    span,
                )
            }
            DatatuiEvent::Paste(text) => {
                Value::record(
                    vec![
                        ("type".into(), Value::string("paste", span)),
                        ("text".into(), Value::string(text, span)),
                        ("timestamp".into(), Value::int(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64, span)),
                    ],
                    span,
                )
            }
        }
    }).collect();
    
    Value::list(nu_events, span)
}

// Helper function to format key modifiers
fn format_modifiers(modifiers: crossterm::event::KeyModifiers, span: Span) -> Vec<Value> {
    let mut result = Vec::new();
    if modifiers.contains(crossterm::event::KeyModifiers::CONTROL) {
        result.push(Value::string("Ctrl", span));
    }
    if modifiers.contains(crossterm::event::KeyModifiers::ALT) {
        result.push(Value::string("Alt", span));
    }
    if modifiers.contains(crossterm::event::KeyModifiers::SHIFT) {
        result.push(Value::string("Shift", span));
    }
    if modifiers.contains(crossterm::event::KeyModifiers::SUPER) {
        result.push(Value::string("Super", span));
    }
    result
}
```

### Widget Storage and Rendering
```rust
// Plugin manages widget storage internally
struct Datatui {
    widgets: HashMap<WidgetId, Box<dyn Widget>>,
    terminal: Option<Terminal<CrosstermBackend<Stdout>>>,
}

// Widget references are custom values returned to Nu
#[derive(Debug, Clone)]
pub struct WidgetRef {
    pub id: WidgetId,
}

impl CustomValue for WidgetRef {
    fn clone_value(&self, span: Span) -> Value {
        Value::Custom { 
            val: Box::new(self.clone()),
            span 
        }
    }
    // ... other CustomValue methods
}

// Render layout containing widget references
fn render_layout(layout: &LayoutDesc, widgets: &HashMap<WidgetId, Box<dyn Widget>>) -> Result<()> {
    // Extract widget references from layout
    // Look up actual widgets from storage
    // Render using ratatui
    for pane in &layout.panes {
        if let Some(widget_ref) = &pane.widget {
            if let Some(widget) = widgets.get(&widget_ref.id) {
                widget.render(frame, pane.area);
            }
        }
    }
}
```

### Nu-Rust Communication (Command-Based)
```rust
// The nu-plugin crate handles all serialization automatically!
// Commands receive parameters and return values directly.

// Widget creation commands store widgets and return references:
impl SimplePluginCommand for ListCommand {
    fn run(&self, plugin: &Datatui, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Extract parameters from call
        let items = call.get_flag_value("items")?.unwrap_or_default();
        let selected = call.get_flag_value("selected")?.unwrap_or_default();
        
        // Create and store widget
        let widget_id = plugin.create_list_widget(items, selected)?;
        
        // Return widget reference as custom value
        Ok(Value::Custom {
            val: Box::new(WidgetRef { id: widget_id }),
            span: call.head
        })
    }
}

// The plugin framework automatically:
// - Serializes/deserializes Nu Values 
// - Handles the JSON-RPC protocol
// - Manages stdin/stdout communication
// - Provides error handling
// - No closures needed - just command parameters and return values
```

## Error Handling Strategy

### Graceful Degradation
- **Plugin crashes**: Return control to Nu with error message
- **Nu closure errors**: Show error in UI, allow retry
- **Terminal errors**: Cleanup terminal state before exit

### Recovery Mechanisms
```rust
// Example: Handle command execution errors
fn handle_command_error(error: &LabeledError) -> Result<Value, LabeledError> {
    eprintln!("datatui error: {}", error);
    
    // For terminal errors, ensure cleanup
    if error.to_string().contains("terminal") {
        let _ = cleanup_terminal();
    }
    
    Err(error.clone())
}

// Widget creation errors
fn create_widget_safely(params: &WidgetParams) -> Result<WidgetRef, LabeledError> {
    match create_widget(params) {
        Ok(widget_ref) => Ok(widget_ref),
        Err(e) => {
            eprintln!("Failed to create widget: {}", e);
            // Return a default/empty widget instead of crashing
            Ok(create_fallback_widget())
        }
    }
}
```

## Performance Considerations

### Optimization Targets
- **State serialization**: Minimize JSON overhead for large datasets
- **Render frequency**: Only re-render on state changes
- **Widget caching**: Leverage ratatui's layout cache
- **Event handling**: Efficient key mapping and dispatch

### Scalability Limits
- **Dataset size**: Target < 10k items for smooth interaction  
- **State complexity**: Deep nesting may impact serialization
- **Update frequency**: Real-time updates limited by Nu closure call overhead

## Testing Strategy

### Unit Tests (Rust)
- Widget rendering with various configurations
- State serialization/deserialization
- Event handler dispatch
- Terminal state management

### Integration Tests (Nu + Rust)
- Full event loop cycle
- Complex state transformations
- Multi-widget layouts
- Error recovery scenarios

### Real-world Validation
- Port jjiles to use datatui
- Build nucess as reference implementation
- Performance testing with large datasets
- User experience validation

## Security Considerations

### Plugin Sandbox
- Plugin cannot access filesystem directly (Nu handles all I/O)
- Terminal control is isolated to plugin process
- Nu closures execute in normal Nu security context

### Input Validation
- Validate UI descriptions from Nu before rendering
- Sanitize terminal control sequences
- Bounds checking for widget dimensions and positions
