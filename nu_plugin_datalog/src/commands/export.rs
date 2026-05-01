use nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nu_protocol::{Category, LabeledError, ListStream, PipelineData, Signature, SyntaxShape, Type};

use crate::conversion::fact_row_to_flat_record;
use crate::plugin::DatalogPlugin;
use crate::state::DatalogState;

pub struct Export;

impl PluginCommand for Export {
    type Plugin = DatalogPlugin;

    fn name(&self) -> &str {
        "datalog export"
    }

    fn description(&self) -> &str {
        "Export derived facts from a datalog-state handle as a stream of records."
    }

    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .rest(
                "predicates",
                SyntaxShape::String,
                "Predicate names to export",
            )
            .switch("all", "Export all derived (IDB) predicates", Some('a'))
            .input_output_type(
                Type::Custom("datalog-state".into()),
                Type::list(Type::record()),
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &DatalogPlugin,
        engine_interface: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        // Extract DatalogState from pipeline input
        let value = input.into_value(call.head)?;
        let custom = value.as_custom_value().map_err(|_| {
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
        let engine_id = state.engine_id;

        let all_flag = call.has_flag("all")?;
        let positional: Vec<String> = call.rest(0)?;

        // Resolve predicates to export
        let predicates_to_export = plugin
            .with_engine(engine_id, |exec_engine| {
                let chase_program = exec_engine.chase_program();

                if all_flag {
                    Ok::<Vec<String>, LabeledError>(
                        chase_program
                            .derived_predicates()
                            .iter()
                            .map(|tag| tag.to_string())
                            .collect(),
                    )
                } else if !positional.is_empty() {
                    Ok(positional)
                } else {
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

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let span = call.head;

        // Collect rows per predicate, then flatten into a single streaming iterator
        let all_rows: Vec<(String, Vec<Vec<nemo::datavalues::AnyDataValue>>)> = predicates_to_export
            .into_iter()
            .map(|pred_name| {
                let tag = nemo::rule_model::components::tag::Tag::new(pred_name.clone());
                let rows = plugin
                    .with_engine(engine_id, |exec_engine| {
                        let rows_opt = rt.block_on(exec_engine.predicate_rows(&tag)).map_err(
                            |e| {
                                LabeledError::new(format!(
                                    "export failed for '{pred_name}': {e}"
                                ))
                            },
                        )?;
                        Ok::<Vec<Vec<nemo::datavalues::AnyDataValue>>, LabeledError>(
                            rows_opt.map(|rows| rows.collect()).unwrap_or_default(),
                        )
                    })
                    .ok_or_else(|| {
                        LabeledError::new("engine not found")
                            .with_label("the state handle may have expired", call.head)
                    })??;
                Ok((pred_name, rows))
            })
            .collect::<Result<Vec<_>, LabeledError>>()?;

        let iter = all_rows.into_iter().flat_map(move |(pred_name, rows)| {
            rows.into_iter()
                .map(move |row| fact_row_to_flat_record(&pred_name, row, span))
        });

        Ok(ListStream::new(iter, span, engine_interface.signals().clone()).into())
    }
}
