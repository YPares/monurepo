use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Signature, SyntaxShape, Value};

use crate::plugin::DatalogPlugin;

pub struct Reason;

impl SimplePluginCommand for Reason {
    type Plugin = DatalogPlugin;

    fn name(&self) -> &str {
        "datalog reason"
    }

    fn description(&self) -> &str {
        "Load Datalog rules, run reasoning to fixpoint, and return a state handle."
    }

    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .named(
                "rules",
                SyntaxShape::String,
                "Inline Datalog rules string",
                Some('r'),
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &DatalogPlugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        let rules: String = call
            .get_flag("rules")?
            .ok_or_else(|| {
                LabeledError::new("missing required flag --rules")
                    .with_label("provide inline Datalog rules", call.head)
            })?;

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let mut engine = rt
            .block_on(nemo::api::load_string(rules))
            .map_err(|e| LabeledError::new(format!("failed to load rules: {e}")))?;

        rt.block_on(nemo::api::reason(&mut engine))
            .map_err(|e| LabeledError::new(format!("reasoning failed: {e}")))?;

        let state = plugin.store_engine(engine);

        Ok(Value::custom(Box::new(state), call.head))
    }
}
