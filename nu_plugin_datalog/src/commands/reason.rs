use nemo::datavalues::AnyDataValue;
use nemo::rule_model::components::fact::Fact;
use nemo::rule_model::components::tag::Tag;
use nemo::rule_model::components::term::Term;
use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Signature, Span, SyntaxShape, Value};
use std::collections::HashMap;

use crate::conversion::nu_value_to_nemo;
use crate::plugin::DatalogPlugin;
use crate::rules_source::RulesSource;

pub struct Reason;

impl SimplePluginCommand for Reason {
    type Plugin = DatalogPlugin;

    fn name(&self) -> &str {
        "datalog reason"
    }

    fn description(&self) -> &str {
        "Load Datalog rules and data, run reasoning to fixpoint, and return a state handle."
    }

    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .named(
                "rules",
                SyntaxShape::String,
                "Inline Datalog rules string",
                Some('r'),
            )
            .named(
                "rules-file",
                SyntaxShape::Filepath,
                "Path to a Datalog rules file",
                Some('f'),
            )
            .named(
                "as",
                SyntaxShape::String,
                "Name for a single table piped in (not a record)",
                Some('a'),
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &DatalogPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        // --- Resolve rules source ---
        let rules_flag: Option<String> = call.get_flag("rules")?;
        let rules_file_flag: Option<String> = call.get_flag("rules-file")?;

        let rules_source = match (rules_flag, rules_file_flag) {
            (Some(_), Some(_)) => {
                return Err(
                    LabeledError::new("--rules and --rules-file are mutually exclusive")
                        .with_label("provide exactly one of --rules or --rules-file", call.head),
                );
            }
            (Some(rules), None) => RulesSource::Inline(rules),
            (None, Some(path)) => {
                // Resolve relative paths against the current working directory
                let path = std::path::PathBuf::from(path);
                let path = if path.is_relative() {
                    let cwd = engine
                        .get_current_dir()
                        .map_err(|e| LabeledError::new(format!("cannot get cwd: {e}")))?;
                    std::path::PathBuf::from(cwd).join(path)
                } else {
                    path
                };
                RulesSource::File(path)
            }
            (None, None) => {
                return Err(
                    LabeledError::new("missing required flag --rules or --rules-file")
                        .with_label("provide inline rules or a rules file", call.head),
                );
            }
        };

        let rules_text = rules_source
            .load()
            .map_err(|e| LabeledError::new(format!("failed to read rules: {e}")))?;

        // --- Parse pipeline input into facts ---
        let input_facts = parse_pipeline_input(input, call)?;

        // --- Build program, inject facts, create engine, reason ---
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let mut program = nemo::api::load_program(rules_text, String::new())
            .map_err(|e| LabeledError::new(format!("failed to parse rules: {e}")))?;

        // Inject facts into the program
        for (predicate, rows) in input_facts {
            let tag = Tag::new(predicate);
            for row in rows {
                let terms: Vec<Term> = row.into_iter().map(|dv| Term::from(dv)).collect();
                let fact = Fact::new(tag.clone(), terms);
                nemo::rule_model::programs::ProgramWrite::add_fact(&mut program, fact);
            }
        }

        let mut exec_engine = rt
            .block_on(nemo::execution::DefaultExecutionEngine::from_program(
                program,
                nemo::execution::execution_parameters::ExecutionParameters::default(),
            ))
            .map_err(|e| LabeledError::new(format!("failed to initialize engine: {e}")))?;

        rt.block_on(nemo::api::reason(&mut exec_engine))
            .map_err(|e| LabeledError::new(format!("reasoning failed: {e}")))?;

        let state = plugin.store_engine(exec_engine);
        Ok(Value::custom(Box::new(state), call.head))
    }
}

/// Parse the pipeline input into a HashMap<predicate_name, Vec<Vec<AnyDataValue>>>.
///
/// Supported input forms:
/// - Nothing (no pipeline input) -> empty facts
/// - Record of tables: {pred1: [[..]; ..], pred2: [[..]; ..]} -> facts per predicate
/// - Single table (requires `--as` flag) -> facts under the given name
fn parse_pipeline_input(
    input: &Value,
    call: &EvaluatedCall,
) -> Result<HashMap<String, Vec<Vec<AnyDataValue>>>, LabeledError> {
    if input.is_nothing() {
        return Ok(HashMap::new());
    }

    match input {
        Value::Record { val, .. } => {
            let mut facts = HashMap::with_capacity(val.len());
            for (pred_name, table_val) in val.iter() {
                let rows = table_to_rows(table_val, call.head, pred_name)?;
                facts.insert(pred_name.clone(), rows);
            }
            Ok(facts)
        }
        Value::List { .. } => {
            let as_name: Option<String> = call.get_flag("as")?;
            match as_name {
                Some(name) => {
                    let rows = table_to_rows(input, call.head, &name)?;
                    let mut facts = HashMap::new();
                    facts.insert(name, rows);
                    Ok(facts)
                }
                None => Err(LabeledError::new(
                    "piping a single table requires --as <predicate_name>",
                )
                .with_label(
                    "use --as to name the predicate, or pipe a record of tables",
                    call.head,
                )),
            }
        }
        _ => Err(LabeledError::new("invalid pipeline input").with_label(
            "expected a record of tables, a single table (with --as), or nothing",
            input.span(),
        )),
    }
}

/// Convert a Nushell list/table value into Vec<Vec<AnyDataValue>>.
fn table_to_rows(
    value: &Value,
    _span: Span,
    pred_name: &str,
) -> Result<Vec<Vec<AnyDataValue>>, LabeledError> {
    let list = value.as_list().map_err(|_| {
        LabeledError::new(format!("expected a table for predicate '{pred_name}'"))
            .with_label("value must be a list of records", value.span())
    })?;

    let mut rows = Vec::with_capacity(list.len());
    for row_val in list {
        let record = row_val.as_record().map_err(|_| {
            LabeledError::new(format!("expected record row in table for '{pred_name}'"))
                .with_label("each element must be a record", row_val.span())
        })?;

        let mut row = Vec::with_capacity(record.len());
        for (_col_name, col_val) in record.iter() {
            match nu_value_to_nemo(col_val)? {
                Some(dv) => row.push(dv),
                None => {
                    // Nothing values are skipped; warn if they appear in the middle
                    // (Nemo doesn't have null, so we just skip)
                }
            }
        }
        rows.push(row);
    }
    Ok(rows)
}
