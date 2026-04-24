use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Record, Signature, SyntaxShape, Value};

use crate::conversion::fact_row_to_record;
use crate::plugin::DatalogPlugin;
use crate::state::DatalogState;

pub struct Export;

impl SimplePluginCommand for Export {
    type Plugin = DatalogPlugin;

    fn name(&self) -> &str {
        "datalog export"
    }

    fn description(&self) -> &str {
        "Export facts from a datalog-state handle as a record of tables."
    }

    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .rest(
                "predicates",
                SyntaxShape::String,
                "Predicate names to export",
            )
            .switch("all", "Export all derived (IDB) predicates", Some('a'))
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &DatalogPlugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let custom = input.as_custom_value().map_err(|_| {
            LabeledError::new("expected datalog-state input")
                .with_label("pipe the result of `datalog reason` here", call.head)
        })?;

        let state = custom
            .as_any()
            .downcast_ref::<DatalogState>()
            .ok_or_else(|| {
                LabeledError::new("expected datalog-state input")
                    .with_label("pipe the result of `datalog reason` here", call.head)
            })?;

        let all_flag = call.has_flag("all")?;
        let positional: Vec<String> = call.rest(0)?;

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let predicates_to_export = plugin
            .with_engine(state.engine_id, |exec_engine| {
                let chase_program = exec_engine.chase_program();

                if all_flag {
                    // Export all derived predicates (IDB)
                    Ok::<Vec<String>, LabeledError>(
                        chase_program
                            .derived_predicates()
                            .iter()
                            .map(|tag| tag.to_string())
                            .collect(),
                    )
                } else if !positional.is_empty() {
                    // Explicit predicate list
                    Ok(positional)
                } else {
                    // Default: predicates from @export directives
                    Ok(chase_program
                        .exports()
                        .iter()
                        .map(|export| export.predicate().to_string())
                        .collect())
                }
            })
            .ok_or_else(|| {
                LabeledError::new("engine not found")
                    .with_label("the state handle may have expired", call.head)
            })??;

        if predicates_to_export.is_empty() {
            return Err(LabeledError::new("no predicates to export").with_label(
                "provide predicate names, use --all, or use @export directives in rules",
                call.head,
            ));
        }

        let mut record = Record::new();

        for pred_name in predicates_to_export {
            let tag = nemo::rule_model::components::tag::Tag::new(pred_name.clone());

            let table = plugin
                .with_engine(state.engine_id, |exec_engine| {
                    let rows_opt = rt.block_on(exec_engine.predicate_rows(&tag)).map_err(|e| {
                        LabeledError::new(format!("export failed for '{pred_name}': {e}"))
                    })?;

                    Ok::<Value, LabeledError>(match rows_opt {
                        Some(rows) => {
                            let records: Vec<Value> =
                                rows.map(|row| fact_row_to_record(row, call.head)).collect();
                            Value::list(records, call.head)
                        }
                        None => Value::list(vec![], call.head),
                    })
                })
                .ok_or_else(|| {
                    LabeledError::new("engine not found")
                        .with_label("the state handle may have expired", call.head)
                })??;

            record.push(pred_name, table);
        }

        Ok(Value::record(record, call.head))
    }
}
