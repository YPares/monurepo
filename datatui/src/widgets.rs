use nu_protocol::{CustomValue, Span, Value, ShellError};
use serde::{Serialize, Deserialize};

pub type WidgetId = u64;

/// Widget reference custom value that gets passed back to Nu
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WidgetRef {
    pub id: WidgetId,
}

#[typetag::serde]
impl CustomValue for WidgetRef {
    fn clone_value(&self, span: Span) -> Value {
        Value::custom(Box::new(self.clone()), span)
    }

    fn type_name(&self) -> String {
        "widget_ref".into()
    }

    fn to_base_value(&self, span: Span) -> Result<Value, ShellError> {
        Ok(Value::string(format!("WidgetRef({})", self.id), span))
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    fn as_mut_any(&mut self) -> &mut dyn std::any::Any {
        self
    }

    fn notify_plugin_on_drop(&self) -> bool {
        true
    }
}

impl nu_protocol::FromValue for WidgetRef {
    fn from_value(v: Value) -> Result<Self, ShellError> {
        match v {
            Value::Custom { val, internal_span } => {
                val.as_any()
                    .downcast_ref()
                    .cloned()
                    .ok_or(ShellError::TypeMismatch {
                        err_message: "Expected a WidgetRef".into(),
                        span: internal_span,
                    })
            }
            _ => Err(ShellError::TypeMismatch {
                err_message: "Expected a WidgetRef".into(),
                span: v.span(),
            }),
        }
    }
}

/// Configuration for various widget types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WidgetConfig {
    List {
        items: Vec<String>,
        selected: Option<usize>,
        scrollable: bool,
        title: Option<String>,
    },
    Text {
        content: String,
        wrap: bool,
        scrollable: bool,
        title: Option<String>,
    },
}

/// Layout configuration for rendering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayoutConfig {
    pub direction: String, // "horizontal" or "vertical"
    pub panes: Vec<PaneConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaneConfig {
    pub widget: WidgetRef,
    pub size: SizeConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum SizeConfig {
    Percentage(String), // "30%"
    Fixed(u16),         // 20
    Fill,               // "*"
}