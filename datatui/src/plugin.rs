use nu_plugin::{EngineInterface, Plugin, PluginCommand};
use nu_protocol::{LabeledError, CustomValue};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use ratatui::{Terminal, backend::CrosstermBackend};
use std::io::Stdout;
use crate::commands::{InitCommand, EventsCommand, RenderCommand, TerminateCommand, ListCommand, TextCommand};
use crate::widgets::{WidgetId, StoredWidget};

pub type LabeledResult<T> = std::result::Result<T, LabeledError>;

pub struct DatatuiPlugin {
    pub widgets: Arc<Mutex<HashMap<WidgetId, StoredWidget>>>,
    pub terminal: Arc<Mutex<Option<Terminal<CrosstermBackend<Stdout>>>>>,
}

impl Default for DatatuiPlugin {
    fn default() -> Self {
        Self {
            widgets: Arc::new(Mutex::new(HashMap::new())),
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

    fn custom_value_dropped(
        &self,
        _engine: &EngineInterface,
        custom_value: Box<dyn CustomValue>,
    ) -> LabeledResult<()> {
        // Handle cleanup when widget references are dropped
        if let Some(widget_ref) = custom_value.as_any().downcast_ref::<crate::widgets::WidgetRef>() {
            // Remove the widget from storage when its reference is dropped
            let mut widgets = self.widgets.lock().unwrap();
            if let Some(_stored_widget) = widgets.remove(&widget_ref.id) {
                // Widget successfully removed from storage
                // #[cfg(debug_assertions)]
                // eprintln!("DEBUG: Cleaned up widget with ID: {}", widget_ref.id);
            }
        }
        Ok(())
    }
}
