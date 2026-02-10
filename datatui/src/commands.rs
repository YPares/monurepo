use nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nu_protocol::{
    LabeledError, PipelineData, Signature, SyntaxShape, Type, Value, Category,
};
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::Stylize,
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

use crate::plugin::{DatatuiPlugin, LabeledResult};
use crate::terminal::{crossterm_event_to_nu_value, init_terminal, restore_terminal};
use crate::widgets::{StoredWidget, LayoutConfig};


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
        plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        // #[cfg(debug_assertions)]
        // eprintln!("init: starting");

        let terminal = init_terminal().map_err(|e| {
            LabeledError::new(format!("Failed to initialize terminal: {}", e))
                .with_label("here", call.head)
        })?;

        // Store the terminal in the plugin state
        let mut terminal_guard = plugin.terminal.lock().unwrap();
        *terminal_guard = Some(terminal);

        // #[cfg(debug_assertions)]
        // eprintln!("init: done");

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
        plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        // Clear the stored terminal first
        {
            let mut terminal_guard = plugin.terminal.lock().unwrap();
            *terminal_guard = None;
        }

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
        "Get terminal events"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        use crossterm::event;
        use std::time::Duration;

        let _guard = engine.enter_foreground()?;

        // Get timeout parameter, default to 100ms
        let timeout_ms = call
            .get_flag("timeout")?
            .map(|v: Value| {
                v.as_duration()
                    .map_err(|e| LabeledError::new(format!("Invalid timeout: {}", e)))
                    .map(|d| (d / 1_000_000) as u64) // Convert nanoseconds to milliseconds
            })
            .transpose()?
            .unwrap_or(100);

        let mut events = Vec::new();

        if event::poll(Duration::from_millis(timeout_ms)).map_err(|e| {
            LabeledError::new(format!("Failed to poll events: {}", e))
                .with_label("here", call.head)
        })? {
            let event = event::read().map_err(|e| {
                LabeledError::new(format!("Failed to read event: {}", e))
                    .with_label("here", call.head)
            })?;

            events.push(crossterm_event_to_nu_value(event, call.head));
        }

        Ok(PipelineData::Value(Value::list(events, call.head), None))
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
            .input_output_type(Type::Nothing, Type::custom("widget"))
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
        "Create a **single-use** list widget"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        // Extract parameters
        let items: Vec<String> = call
            .get_flag("items")?
            .map(|v: Value| -> Result<Vec<String>, LabeledError> {
                let list = v.as_list()
                    .map_err(|e| LabeledError::new(format!("Invalid items: {}", e)))?;
                Ok(list
                    .iter()
                    .map(|item| item.coerce_string().unwrap_or_else(|e| e.to_string()))
                    .collect())
            })
            .transpose()?
            .unwrap_or_default();

        let title: Option<String> = call
            .get_flag("title")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|e| e.to_string()));

        // Create ratatui List widget directly
        let list_items: Vec<ListItem> = items
            .into_iter()
            .map(|item| ListItem::new(item))
            .collect();

        let mut list = List::new(list_items)
            .highlight_style(ratatui::style::Style::default().reversed())
            ;

        if let Some(title) = title {
            list = list.block(Block::default().borders(Borders::ALL).title(title));
        }

        // Return the widget directly
        let stored_widget = StoredWidget::List(list);
        Ok(PipelineData::Value(
            Value::custom(Box::new(stored_widget), call.head),
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
            .input_output_type(Type::Nothing, Type::custom("widget"))
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
        "Create a **single-use** text widget"
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> LabeledResult<PipelineData> {
        let content: String = call
            .get_flag("content")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|e| e.to_string()))
            .unwrap_or_default();

        let title: Option<String> = call
            .get_flag("title")?
            .map(|v: Value| v.coerce_string().unwrap_or_else(|e| e.to_string()));

        // Create ratatui Paragraph widget directly
        let mut paragraph = Paragraph::new(content);

        if let Some(title) = title {
            paragraph = paragraph.block(Block::default().borders(Borders::ALL).title(title));
        }

        // Return the widget directly
        let stored_widget = StoredWidget::Paragraph(paragraph);
        Ok(PipelineData::Value(
            Value::custom(Box::new(stored_widget), call.head),
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
            .input_output_type(Type::custom("widget"), Type::Nothing)
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
        match input {
            PipelineData::Value(Value::Custom { val, .. }, _) => {
                // Single widget rendering
                if let Some(stored_widget) = val.as_any().downcast_ref::<StoredWidget>() {
                    render_widget(plugin, stored_widget)?;
                    return Ok(PipelineData::empty());
                }
            }
            PipelineData::Value(Value::Record { val, .. }, _) => {
                // Layout rendering with multiple widgets
                let layout_config = LayoutConfig::from_nu_record(&val)?;
                render_layout(plugin, &layout_config)?;
                return Ok(PipelineData::empty());
            }
            _ => {}
        }

        Err(LabeledError::new("Expected a widget or layout configuration")
            .with_label("here", call.head))
    }
}

/// Render a single widget to the terminal
fn render_widget(plugin: &DatatuiPlugin, stored_widget: &StoredWidget) -> Result<(), LabeledError> {
    // Get the stored terminal
    let mut terminal_guard = plugin.terminal.lock().unwrap();
    let terminal = terminal_guard.as_mut()
        .ok_or_else(|| LabeledError::new("Terminal not initialized. Run 'datatui init' first."))?;

    // Render the widget
    terminal.draw(|frame| {
        let size = frame.area();
        stored_widget.render(frame, size);
    })
    .map_err(|e| LabeledError::new(format!("Failed to render widget: {}", e)))?;

    Ok(())
}

/// Render a layout with multiple widgets to the terminal
fn render_layout(plugin: &DatatuiPlugin, layout_config: &LayoutConfig) -> Result<(), LabeledError> {
    // Get the stored terminal
    let mut terminal_guard = plugin.terminal.lock().unwrap();
    let terminal = terminal_guard.as_mut()
        .ok_or_else(|| LabeledError::new("Terminal not initialized. Run 'datatui init' first."))?;

    // Render the layout
    terminal.draw(|frame| {
        render_layout_frame(frame, layout_config)
    })
    .map_err(|e| LabeledError::new(format!("Failed to render layout: {}", e)))?;

    Ok(())
}

/// Render layout within a frame
fn render_layout_frame(
    frame: &mut Frame,
    layout_config: &LayoutConfig,
) {
    let total_area = frame.area();

    // Convert direction
    let direction = match layout_config.direction.as_str() {
        "horizontal" => Direction::Horizontal,
        "vertical" => Direction::Vertical,
        _ => Direction::Vertical, // default
    };

    // Convert sizes to constraints
    let constraints: Vec<Constraint> = layout_config
        .panes
        .iter()
        .map(|pane| pane.size.to_constraint())
        .collect();

    // Create layout
    let layout = Layout::default()
        .direction(direction)
        .constraints(constraints);

    let areas = layout.split(total_area);

    // Render each widget in its area
    for (i, pane) in layout_config.panes.iter().enumerate() {
        if i >= areas.len() {
            continue;
        }

        let area = areas[i];

        pane.widget.render(frame, area);
    }
}

