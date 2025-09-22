use crossterm::{
    event::{Event, KeyCode, KeyModifiers},
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    ExecutableCommand,
};
use miette::{IntoDiagnostic, Result};
use nu_protocol::{Span, Value};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};
use std::time::{SystemTime, UNIX_EPOCH};

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

pub fn crossterm_event_to_nu_value(event: Event, span: Span) -> Value {
    match event {
        Event::Key(key_event) => {
            let record = vec![
                ("type".into(), Value::string("key", span)),
                ("key".into(), Value::string(format_key_code(key_event.code), span)),
                ("modifiers".into(), format_modifiers(key_event.modifiers, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        Event::Mouse(mouse_event) => {
            let record = vec![
                ("type".into(), Value::string("mouse", span)),
                ("x".into(), Value::int(mouse_event.column as i64, span)),
                ("y".into(), Value::int(mouse_event.row as i64, span)),
                ("button".into(), Value::string(format!("{:?}", mouse_event.kind), span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        Event::Resize(w, h) => {
            let record = vec![
                ("type".into(), Value::string("resize", span)),
                ("width".into(), Value::int(w as i64, span)),
                ("height".into(), Value::int(h as i64, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        Event::Paste(text) => {
            let record = vec![
                ("type".into(), Value::string("paste", span)),
                ("text".into(), Value::string(text, span)),
                ("timestamp".into(), get_timestamp(span)),
            ];

            Value::record(record.into_iter().collect(), span)
        }
        _ => {
            // For any other event types, create a generic record
            let record = vec![
                ("type".into(), Value::string("unknown", span)),
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
