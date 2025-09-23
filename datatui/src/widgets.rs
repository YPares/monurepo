use nu_protocol::{CustomValue, Span, Value, ShellError, LabeledError};
use serde::{Serialize, Deserialize};
use ratatui::widgets::{List, Paragraph};


/// Direct storage of ratatui widgets
#[derive(Debug, Clone)]
pub enum StoredWidget {
    List(List<'static>),
    Paragraph(Paragraph<'static>),
}

impl StoredWidget {
    pub fn render(&self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect) {
        match self {
            StoredWidget::List(list) => frame.render_widget(list.clone(), area),
            StoredWidget::Paragraph(paragraph) => frame.render_widget(paragraph.clone(), area),
        }
    }
}

#[typetag::serde]
impl CustomValue for StoredWidget {
    fn clone_value(&self, span: Span) -> Value {
        Value::custom(Box::new(self.clone()), span)
    }

    fn type_name(&self) -> String {
        "widget".into()
    }

    fn to_base_value(&self, span: Span) -> Result<Value, ShellError> {
        let widget_type = match self {
            StoredWidget::List(_) => "List",
            StoredWidget::Paragraph(_) => "Paragraph",
        };
        Ok(Value::string(format!("Widget({})", widget_type), span))
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    fn as_mut_any(&mut self) -> &mut dyn std::any::Any {
        self
    }
}

impl nu_protocol::FromValue for StoredWidget {
    fn from_value(v: Value) -> Result<Self, ShellError> {
        match v {
            Value::Custom { val, internal_span } => {
                val.as_any()
                    .downcast_ref()
                    .cloned()
                    .ok_or(ShellError::TypeMismatch {
                        err_message: "Expected a StoredWidget".into(),
                        span: internal_span,
                    })
            }
            _ => Err(ShellError::TypeMismatch {
                err_message: "Expected a StoredWidget".into(),
                span: v.span(),
            }),
        }
    }
}

/// Layout configuration for rendering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayoutConfig {
    pub direction: String, // "horizontal" or "vertical"
    pub panes: Vec<PaneConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaneConfig {
    pub widget: StoredWidget,
    pub size: SizeConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum SizeConfig {
    Percentage(String), // "30%"
    Fixed(u16),         // 20
    Fill(String),       // "*"
}

impl SizeConfig {
    /// Parse size from Nu value
    pub fn from_nu_value(value: &Value) -> Result<Self, String> {
        match value {
            Value::String { val, .. } => {
                if val == "*" {
                    Ok(SizeConfig::Fill("*".to_string()))
                } else if val.ends_with('%') {
                    Ok(SizeConfig::Percentage(val.clone()))
                } else {
                    Err(format!("Invalid string size format: {}", val))
                }
            }
            Value::Int { val, .. } => {
                if *val >= 0 && *val <= u16::MAX as i64 {
                    Ok(SizeConfig::Fixed(*val as u16))
                } else {
                    Err(format!("Size {} out of range for u16", val))
                }
            }
            _ => Err(format!("Size must be string or integer, got {:?}", value.get_type())),
        }
    }

    /// Convert to ratatui Constraint
    pub fn to_constraint(&self) -> ratatui::layout::Constraint {
        match self {
            SizeConfig::Percentage(s) => {
                if let Some(num_str) = s.strip_suffix('%') {
                    if let Ok(percentage) = num_str.parse::<u16>() {
                        ratatui::layout::Constraint::Percentage(percentage)
                    } else {
                        ratatui::layout::Constraint::Percentage(50) // fallback
                    }
                } else {
                    ratatui::layout::Constraint::Percentage(50) // fallback
                }
            }
            SizeConfig::Fixed(size) => ratatui::layout::Constraint::Length(*size),
            SizeConfig::Fill(_) => ratatui::layout::Constraint::Fill(1),
        }
    }
}

impl LayoutConfig {
    /// Parse layout configuration from Nu record
    pub fn from_nu_record(record: &nu_protocol::record::Record) -> Result<Self, LabeledError> {
        // Get the layout field
        let layout_value = record.get("layout")
            .ok_or_else(|| LabeledError::new("Layout record must have 'layout' field"))?;

        let layout_record = layout_value.as_record()
            .map_err(|e| LabeledError::new(format!("Layout must be a record: {}", e)))?;

        // Parse direction
        let direction = layout_record.get("direction")
            .and_then(|v| v.coerce_string().ok())
            .unwrap_or_else(|| "vertical".to_string());

        // Parse panes
        let panes_value = layout_record.get("panes")
            .ok_or_else(|| LabeledError::new("Layout must have 'panes' field"))?;

        let panes_list = panes_value.as_list()
            .map_err(|e| LabeledError::new(format!("Panes must be a list: {}", e)))?;

        let mut panes = Vec::new();
        for (i, pane_value) in panes_list.iter().enumerate() {
            let pane_record = pane_value.as_record()
                .map_err(|e| LabeledError::new(format!("Pane {} must be a record: {}", i, e)))?;

            // Parse widget
            let widget_value = pane_record.get("widget")
                .ok_or_else(|| LabeledError::new(format!("Pane {} must have 'widget' field", i)))?;

            let stored_widget = if let Value::Custom { val, .. } = widget_value {
                val.as_any().downcast_ref::<StoredWidget>()
                    .ok_or_else(|| LabeledError::new(format!("Pane {} widget must be a StoredWidget", i)))?
                    .clone()
            } else {
                return Err(LabeledError::new(format!("Pane {} widget must be a custom StoredWidget value", i)));
            };

            // Parse size
            let size_value = pane_record.get("size")
                .ok_or_else(|| LabeledError::new(format!("Pane {} must have 'size' field", i)))?;

            let size = SizeConfig::from_nu_value(size_value)
                .map_err(|e| LabeledError::new(format!("Pane {} size error: {}", i, e)))?;

            panes.push(PaneConfig { widget: stored_widget, size });
        }

        Ok(LayoutConfig { direction, panes })
    }
}
