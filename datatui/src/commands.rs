use nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nu_protocol::{
    LabeledError, PipelineData, Signature, SyntaxShape, Type, Value, Category,
};
use ratatui::{
    backend::CrosstermBackend,
    style::Stylize,
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Terminal,
};
use std::io;

use crate::plugin::{DatatuiPlugin, LabeledResult};
use crate::terminal::{collect_events, events_to_nu_values, init_terminal, restore_terminal};
use crate::widgets::{WidgetRef, WidgetId, WidgetConfig};

static mut WIDGET_COUNTER: WidgetId = 0;

fn next_widget_id() -> WidgetId {
    unsafe {
        WIDGET_COUNTER += 1;
        WIDGET_COUNTER
    }
}

// Terminal lifecycle commands

pub struct InitCommand;

impl PluginCommand for InitCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui init"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui init")
            .input_output_type(Type::Nothing, Type::Nothing)
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Initialize terminal for TUI mode"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        let _terminal = init_terminal().map_err(|e| {
            LabeledError::new(format!("Failed to initialize terminal: {}", e))
                .with_label("here", call.head)
        })?;

        // Note: We can't actually store the terminal in the plugin due to mutability constraints
        // For now, we'll just initialize and let each command manage its own terminal access
        Ok(PipelineData::empty())
    }
}

pub struct TerminateCommand;

impl PluginCommand for TerminateCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui terminate"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui terminate")
            .input_output_type(Type::Nothing, Type::Nothing)
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Restore terminal to normal mode"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        restore_terminal().map_err(|e| {
            LabeledError::new(format!("Failed to restore terminal: {}", e))
                .with_label("here", call.head)
        })?;

        Ok(PipelineData::empty())
    }
}

// Event handling

pub struct EventsCommand;

impl PluginCommand for EventsCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui events"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui events")
            .input_output_type(Type::Nothing, Type::List(Box::new(Type::Record(vec![].into()))))
            .named(
                "timeout",
                SyntaxShape::Duration,
                "Timeout for non-blocking operation",
                Some('t'),
            )
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Get terminal events (blocking until events are available)"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        let events = collect_events().map_err(|e| {
            LabeledError::new(format!("Failed to collect events: {}", e))
                .with_label("here", call.head)
        })?;

        let nu_events = events_to_nu_values(events, call.head);
        Ok(PipelineData::Value(nu_events, None))
    }
}

// Widget creation commands

pub struct ListCommand;

impl PluginCommand for ListCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui list"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui list")
            .input_output_type(Type::Nothing, Type::custom("widget_ref"))
            .named(
                "items",
                SyntaxShape::List(Box::new(SyntaxShape::String)),
                "List of items to display",
                Some('i'),
            )
            .named(
                "selected",
                SyntaxShape::Int,
                "Index of selected item",
                Some('s'),
            )
            .switch("scrollable", "Enable scrolling", Some('S'))
            .named(
                "title",
                SyntaxShape::String,
                "Title for the list widget",
                Some('t'),
            )
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Create a list widget"
    }

    fn run(
        &self,
        plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        let widget_id = next_widget_id();

        // Extract parameters
        let items: Vec<String> = call
            .get_flag("items")?
            .map(|v: Value| -> Result<Vec<String>, LabeledError> {
                let list = v.as_list()
                    .map_err(|e| LabeledError::new(format!("Invalid items: {}", e)))?;
                Ok(list
                    .iter()
                    .map(|item| item.coerce_string().unwrap_or_else(|_| "".to_string()))
                    .collect())
            })
            .transpose()?
            .unwrap_or_default();

        let selected: Option<usize> = call
            .get_flag("selected")?
            .map(|v: Value| v.as_int().map_err(|e| LabeledError::new(format!("Invalid selected: {}", e))))
            .transpose()?
            .map(|i| i as usize);

        let scrollable = call.has_flag("scrollable")?;

        let title: Option<String> = call
            .get_flag("title")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|_| "".to_string()));

        // Store widget configuration
        let widget_config = WidgetConfig::List {
            items,
            selected,
            scrollable,
            title,
        };

        plugin.widgets.lock().unwrap().insert(widget_id, widget_config);

        let widget_ref = WidgetRef { id: widget_id };
        Ok(PipelineData::Value(
            Value::custom(Box::new(widget_ref), call.head),
            None,
        ))
    }
}

pub struct TextCommand;

impl PluginCommand for TextCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui text"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui text")
            .input_output_type(Type::Nothing, Type::custom("widget_ref"))
            .named(
                "content",
                SyntaxShape::String,
                "Text content to display",
                Some('c'),
            )
            .switch("wrap", "Enable text wrapping", Some('w'))
            .switch("scrollable", "Enable scrolling", Some('S'))
            .named(
                "title",
                SyntaxShape::String,
                "Title for the text widget",
                Some('t'),
            )
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Create a text widget"
    }

    fn run(
        &self,
        plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        let widget_id = next_widget_id();

        let content: String = call
            .get_flag("content")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|_| "".to_string()))
            .unwrap_or_default();

        let wrap = call.has_flag("wrap")?;
        let scrollable = call.has_flag("scrollable")?;

        let title: Option<String> = call
            .get_flag("title")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|_| "".to_string()));

        // Store widget configuration
        let widget_config = WidgetConfig::Text {
            content,
            wrap,
            scrollable,
            title,
        };

        plugin.widgets.lock().unwrap().insert(widget_id, widget_config);

        let widget_ref = WidgetRef { id: widget_id };
        Ok(PipelineData::Value(
            Value::custom(Box::new(widget_ref), call.head),
            None,
        ))
    }
}

// Rendering command

pub struct RenderCommand;

impl PluginCommand for RenderCommand {
    type Plugin = DatatuiPlugin;

    fn name(&self) -> &str {
        "datatui render"
    }

    fn signature(&self) -> Signature {
        Signature::build("datatui render")
            .input_output_type(Type::Any, Type::Nothing)
            .category(Category::Experimental)
    }

    fn description(&self) -> &str {
        "Render UI layout to terminal"
    }

    fn run(
        &self,
        plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        // For single widget rendering, handle directly
        match input {
            PipelineData::Value(Value::Custom { val, .. }, _) => {
                // Try to downcast to WidgetRef
                if let Some(widget_ref) = val.as_any().downcast_ref::<WidgetRef>() {
                    render_single_widget(plugin, widget_ref)?;
                    return Ok(PipelineData::empty());
                }
            }
            PipelineData::Value(Value::Record { val, .. }, _) => {
                // Handle layout record (for future implementation)
                let _layout_record = val;
                // TODO: Parse layout configuration and render multiple widgets
                return Err(LabeledError::new("Layout rendering not yet implemented")
                    .with_label("here", call.head));
            }
            _ => {}
        }

        Err(LabeledError::new("Expected a widget reference or layout configuration")
            .with_label("here", call.head))
    }
}

/// Render a single widget to the terminal
fn render_single_widget(plugin: &DatatuiPlugin, widget_ref: &WidgetRef) -> Result<(), LabeledError> {
    // Get widget configuration
    let widgets = plugin.widgets.lock().unwrap();
    let widget_config = widgets.get(&widget_ref.id)
        .ok_or_else(|| LabeledError::new(format!("Widget with ID {} not found", widget_ref.id)))?;

    // Initialize terminal
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend)
        .map_err(|e| LabeledError::new(format!("Failed to create terminal: {}", e)))?;

    // Render the widget
    terminal.draw(|frame| {
        let size = frame.area();

        match widget_config {
            WidgetConfig::List { items, selected, title, .. } => {
                let list_items: Vec<ListItem> = items
                    .iter()
                    .map(|item| ListItem::new(item.clone()))
                    .collect();

                let mut list = List::new(list_items)
                    .highlight_style(ratatui::style::Style::default().reversed());

                if let Some(title) = title {
                    list = list.block(Block::default().borders(Borders::ALL).title(title.clone()));
                }

                // Handle selection state if needed
                if selected.is_some() {
                    // TODO: Use StatefulWidget for proper selection handling
                }

                frame.render_widget(list, size);
            }
            WidgetConfig::Text { content, title, .. } => {
                let mut paragraph = Paragraph::new(content.clone());

                if let Some(title) = title {
                    paragraph = paragraph.block(Block::default().borders(Borders::ALL).title(title.clone()));
                }

                frame.render_widget(paragraph, size);
            }
        }
    })
    .map_err(|e| LabeledError::new(format!("Failed to render widget: {}", e)))?;

    Ok(())
}