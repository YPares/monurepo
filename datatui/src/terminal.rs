use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEvent},
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    ExecutableCommand,
};
use miette::{IntoDiagnostic, Result};
use nu_protocol::{Span, Value};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub type DatatuiTerminal = Terminal<CrosstermBackend<Stdout>>;

/// Initialize terminal for TUI mode
pub fn init_terminal() -> Result<DatatuiTerminal> {
    enable_raw_mode().into_diagnostic()?;
    io::stdout()
        .execute(EnterAlternateScreen)
        .into_diagnostic()?;

    let backend = CrosstermBackend::new(io::stdout());
    let terminal = Terminal::new(backend).into_diagnostic()?;

    Ok(terminal)
}

/// Restore terminal to normal mode
pub fn restore_terminal() -> Result<()> {
    disable_raw_mode().into_diagnostic()?;
    io::stdout()
        .execute(LeaveAlternateScreen)
        .into_diagnostic()?;
    Ok(())
}

/// Event types that can be received from the terminal
#[derive(Debug, Clone)]
pub enum DatatuiEvent {
    Key(KeyEvent),
    Mouse(MouseEvent),
    Resize(u16, u16),
    Paste(String),
}

/// Collect events from the terminal
pub fn collect_events() -> Result<Vec<DatatuiEvent>> {
    let mut events = Vec::new();

    // Block for the first event
    match event::read().into_diagnostic()? {
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
    while event::poll(Duration::from_millis(0)).into_diagnostic()? {
        match event::read().into_diagnostic()? {
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

    Ok(events)
}

/// Convert terminal events to Nu values
pub fn events_to_nu_values(events: Vec<DatatuiEvent>, span: Span) -> Value {
    let nu_events = events
        .into_iter()
        .map(|event| event_to_nu_value(event, span))
        .collect();

    Value::list(nu_events, span)
}

fn event_to_nu_value(event: DatatuiEvent, span: Span) -> Value {
    match event {
        DatatuiEvent::Key(key_event) => {
            let record = vec![
                ("type".into(), Value::string("key", span)),
                ("key".into(), Value::string(format_key_code(key_event.code), span)),
                ("modifiers".into(), format_modifiers(key_event.modifiers, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        DatatuiEvent::Mouse(mouse_event) => {
            let record = vec![
                ("type".into(), Value::string("mouse", span)),
                ("x".into(), Value::int(mouse_event.column as i64, span)),
                ("y".into(), Value::int(mouse_event.row as i64, span)),
                ("button".into(), Value::string(format!("{:?}", mouse_event.kind), span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        DatatuiEvent::Resize(w, h) => {
            let record = vec![
                ("type".into(), Value::string("resize", span)),
                ("width".into(), Value::int(w as i64, span)),
                ("height".into(), Value::int(h as i64, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        DatatuiEvent::Paste(text) => {
            let record = vec![
                ("type".into(), Value::string("paste", span)),
                ("text".into(), Value::string(text, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
    }
}

fn format_key_code(code: KeyCode) -> String {
    match code {
        KeyCode::Backspace => "Backspace".into(),
        KeyCode::Enter => "Enter".into(),
        KeyCode::Left => "Left".into(),
        KeyCode::Right => "Right".into(),
        KeyCode::Up => "Up".into(),
        KeyCode::Down => "Down".into(),
        KeyCode::Home => "Home".into(),
        KeyCode::End => "End".into(),
        KeyCode::PageUp => "PageUp".into(),
        KeyCode::PageDown => "PageDown".into(),
        KeyCode::Tab => "Tab".into(),
        KeyCode::BackTab => "BackTab".into(),
        KeyCode::Delete => "Delete".into(),
        KeyCode::Insert => "Insert".into(),
        KeyCode::F(n) => format!("F{}", n),
        KeyCode::Char(c) => c.to_string(),
        KeyCode::Null => "Null".into(),
        KeyCode::Esc => "Escape".into(),
        KeyCode::CapsLock => "CapsLock".into(),
        KeyCode::ScrollLock => "ScrollLock".into(),
        KeyCode::NumLock => "NumLock".into(),
        KeyCode::PrintScreen => "PrintScreen".into(),
        KeyCode::Pause => "Pause".into(),
        KeyCode::Menu => "Menu".into(),
        KeyCode::KeypadBegin => "KeypadBegin".into(),
        KeyCode::Media(_) => "Media".into(),
        KeyCode::Modifier(_) => "Modifier".into(),
    }
}

fn format_modifiers(modifiers: KeyModifiers, span: Span) -> Value {
    let mut result = Vec::new();

    if modifiers.contains(KeyModifiers::CONTROL) {
        result.push(Value::string("Ctrl", span));
    }
    if modifiers.contains(KeyModifiers::ALT) {
        result.push(Value::string("Alt", span));
    }
    if modifiers.contains(KeyModifiers::SHIFT) {
        result.push(Value::string("Shift", span));
    }
    if modifiers.contains(KeyModifiers::SUPER) {
        result.push(Value::string("Super", span));
    }
    if modifiers.contains(KeyModifiers::HYPER) {
        result.push(Value::string("Hyper", span));
    }
    if modifiers.contains(KeyModifiers::META) {
        result.push(Value::string("Meta", span));
    }

    Value::list(result, span)
}

fn get_timestamp(span: Span) -> Value {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    Value::int(timestamp, span)
}
