# datatui Architecture Deep Dive

## Plugin Architecture Overview

```
┌─────────────────┐    JSON-RPC     ┌──────────────────┐
│   Nushell       │◄────────────────┤   datatui        │
│   Script        │                 │   Plugin         │
│                 │                 │                  │
│ • State mgmt    │    State +      │ • Terminal       │
│ • Event logic   │    UI Desc      │   control        │
│ • Data proc.    │                 │ • Ratatui        │ 
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
  │       let events = datatui events  # Get events    │
  │       $state = process_events($state, $events)     │
  │       let widgets = create_widgets($state)          │
  │       {layout: ...} | datatui render               │
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
  │  • Event collection (crossterm::event::read)       │
  │  • Widget storage (HashMap<WidgetId, Widget>)       │
  │  • Rendering (ratatui draw calls)                   │
  │  • No application state - Nu manages everything    │
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
  ui: {
    layout: {
      direction: horizontal
      panes: [
        {
          widget: {
            type: "list"
            id: "file_list"      # Required for event targeting
            items: ["file1.txt", "file2.txt", "document.txt"]
            selected: 3
            scrollable: true
            title: "Files"
          }
          size: "30%"
        }
        {
          widget: {
            type: "text"
            content: "Document contents here..."
            wrap: true
            title: "Preview"
          }
          size: "*"
        }
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
      direction: horizontal
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
use nu_plugin::{serve_plugin, Plugin, SimplePluginCommand, MsgPackSerializer};
use nu_plugin::{EngineInterface, EvaluatedCall};
use nu_protocol::{LabeledError, Signature, Value, Type};

struct DatatUI;
struct InitCommand;
struct EventsCommand;
struct RenderCommand;
struct TerminateCommand;
struct ListCommand;
struct TextCommand;

impl Plugin for DatatUI {
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
    type Plugin = DatatUI;
    
    fn name(&self) -> &str { "datatui init" }
    fn description(&self) -> &str { "Initialize terminal for TUI mode" }
    
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface, 
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Initialize terminal, enter raw mode, setup crossterm
        setup_terminal()?;
        Ok(Value::Nothing { span: call.head })
    }
}

impl SimplePluginCommand for EventsCommand {
    type Plugin = DatatUI;
    
    fn name(&self) -> &str { "datatui events" }
    fn description(&self) -> &str { "Get terminal events (blocking)" }
    
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Call crossterm::event::read(), convert to Nu values
        let events = read_crossterm_events()?;
        Ok(events_to_nu_value(events, call.head))
    }
}

impl SimplePluginCommand for ListCommand {
    type Plugin = DatatUI;
    
    fn name(&self) -> &str { "datatui list" }
    fn description(&self) -> &str { "Create a list widget" }
    fn signature(&self) -> Signature {
        Signature::build("datatui list")
            .named("items", SyntaxShape::List(Box::new(SyntaxShape::Any)), "List items", None)
            .named("selected", SyntaxShape::Int, "Selected index", None)
            .switch("scrollable", "Make list scrollable", None)
    }
    
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        // Create widget, store in plugin, return widget ID
        let widget_id = create_list_widget(call)?;
        Ok(Value::Custom { 
            val: Box::new(WidgetRef { id: widget_id }),
            span: call.head 
        })
    }
}

fn main() {
    serve_plugin(&DatatUI, MsgPackSerializer);
}

// Simple command implementations for user-controlled architecture
impl SimplePluginCommand for EventsCommand {
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        let events = collect_crossterm_events()?;
        Ok(events_to_nu_values(events, call.head))
    }
}

impl SimplePluginCommand for RenderCommand {
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface,
           call: &EvaluatedCall, input: &Value) -> Result<Value, LabeledError> {
        let layout = input.as_record()?;
        render_layout_to_terminal(layout)?;
        Ok(Value::Nothing { span: call.head })
    }
}

// Core event collection function
fn collect_crossterm_events() -> Result<Vec<CrosstermEvent>, Error> {
    let mut events = Vec::new();
    
    // Collect all available events (non-blocking after first)
    if crossterm::event::poll(Duration::from_millis(0))? {
        loop {
            match crossterm::event::read()? {
                Event::Key(key_event) if key_event.kind == KeyEventKind::Press => {
                    events.push(CrosstermEvent::Key(key_event));
                }
                Event::Mouse(mouse_event) => {
                    events.push(CrosstermEvent::Mouse(mouse_event));
                }
                Event::Resize(w, h) => {
                    events.push(CrosstermEvent::Resize(w, h));
                }
                Event::Paste(text) => {
                    events.push(CrosstermEvent::Paste(text));
                }
                _ => {} // Ignore other events
            }
            
            // Check if more events are available (non-blocking)
            if !crossterm::event::poll(Duration::from_millis(0))? {
                break;
            }
        }
    }
    
    Ok(events)
}

// Convert crossterm events to Nu values
fn events_to_nu_values(events: Vec<CrosstermEvent>, span: Span) -> Value {
    let nu_events = events.into_iter().map(|event| {
        match event {
            CrosstermEvent::Key(key_event) => {
                Value::Record {
                    cols: vec!["type".into(), "key".into(), "modifiers".into(), "timestamp".into()],
                    vals: vec![
                        Value::String { val: "key".into(), span },
                        Value::String { val: format!("{:?}", key_event.code), span },
                        Value::List { vals: format_modifiers(key_event.modifiers, span), span },
                        Value::Int { val: chrono::Utc::now().timestamp_millis(), span },
                    ],
                    span,
                }
            }
            CrosstermEvent::Resize(w, h) => {
                Value::Record {
                    cols: vec!["type".into(), "width".into(), "height".into(), "timestamp".into()],
                    vals: vec![
                        Value::String { val: "resize".into(), span },
                        Value::Int { val: w as i64, span },
                        Value::Int { val: h as i64, span },
                        Value::Int { val: chrono::Utc::now().timestamp_millis(), span },
                    ],
                    span,
                }
            }
            // ... other event types
        }
    }).collect();
    
    Value::List { vals: nu_events, span }
}
```

### Widget Storage and Rendering
```rust
// Plugin manages widget storage internally
struct DatatUI {
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
    fn run(&self, plugin: &DatatUI, engine: &EngineInterface,
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