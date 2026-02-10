use nu_plugin::{EngineInterface, Plugin, PluginCommand};
use nu_protocol::{LabeledError, CustomValue};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use ratatui::{Terminal, backend::CrosstermBackend};
use std::io::Stdout;
use crate::commands::{InitCommand, EventsCommand, RenderCommand, TerminateCommand, ListCommand, TextCommand};

pub type LabeledResult<T> = std::result::Result<T, LabeledError>;

pub struct DatatuiPlugin {
    pub terminal: Arc<Mutex<Option<Terminal<CrosstermBackend<Stdout>>>>>,
}

impl Default for DatatuiPlugin {
    fn default() -> Self {
        Self {
            terminal: Arc::new(Mutex::new(None)),
        }
    }
}

impl Plugin for DatatuiPlugin {
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
        ]
    }

}
