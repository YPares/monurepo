use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Record, Signature, SyntaxShape, Span, Value};

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

        let predicates: Vec<String> = call.rest(0)?;
        if predicates.is_empty() {
            return Err(LabeledError::new("no predicates specified")
                .with_label("provide at least one predicate name", call.head));
        }

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let mut record = Record::new();

        for pred_name in predicates {
            let tag = nemo::rule_model::components::tag::Tag::new(pred_name.clone());

            let table = plugin
                .with_engine(state.engine_id, |engine| {
                    let rows_opt = rt
                        .block_on(engine.predicate_rows(&tag))
                        .map_err(|e| {
                            LabeledError::new(format!("export failed for '{pred_name}': {e}"))
                        })?;

                    Ok::<Value, LabeledError>(match rows_opt {
                        Some(rows) => {
                            let records: Vec<Value> =
                                rows.map(|row| row_to_record(row, call.head)).collect();
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

fn row_to_record(row: Vec<nemo::datavalues::AnyDataValue>, span: Span) -> Value {
    let mut record = Record::new();
    for (i, val) in row.iter().enumerate() {
        let col_name = format!("col{i}");
        record.push(col_name, Value::string(val.to_string(), span));
    }
    Value::record(record, span)
}
