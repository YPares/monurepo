use std::any::Any;

use nu_protocol::{CustomValue, ShellError, Span, Value};
use serde::{Deserialize, Serialize};

/// Opaque handle to a Datalog engine stored in the plugin.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DatalogState {
    pub engine_id: u64,
}

#[typetag::serde]
impl CustomValue for DatalogState {
    fn clone_value(&self, span: Span) -> Value {
        Value::custom(Box::new(self.clone()), span)
    }

    fn type_name(&self) -> String {
        "datalog-state".to_string()
    }

    fn to_base_value(&self, span: Span) -> Result<Value, ShellError> {
        Ok(Value::string(
            format!("datalog-state({})", self.engine_id),
            span,
        ))
    }

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn as_mut_any(&mut self) -> &mut dyn Any {
        self
    }

    fn notify_plugin_on_drop(&self) -> bool {
        true
    }
}
