use nemo::datavalues::AnyDataValue;
use nemo::rule_model::components::fact::Fact;
use nemo::rule_model::components::tag::Tag;
use nemo::rule_model::components::term::Term;
use nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nu_protocol::{Category, LabeledError, PipelineData, Signature, Span, SyntaxShape, Value};
use std::collections::HashMap;

use crate::conversion::nu_value_to_nemo;
use crate::plugin::DatalogPlugin;
use crate::rules_source::RulesSource;

pub struct Reason;

impl PluginCommand for Reason {
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
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &DatalogPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
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
        let input_facts = collect_facts(input, call.head)?;

        // --- Build program, inject facts, create engine, reason ---
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| LabeledError::new(format!("tokio runtime error: {e}")))?;

        let mut program = nemo::api::load_program(rules_text, String::new())
            .map_err(|e| LabeledError::new(format!("failed to parse rules: {e}")))?;

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
        Ok(PipelineData::Value(
            Value::custom(Box::new(state), call.head),
            None,
        ))
    }
}

/// Collect facts from pipeline input into a HashMap<predicate_name, Vec<Vec<AnyDataValue>>>.
///
/// Supported input forms:
/// - Nothing (no pipeline input) -> empty facts
/// - Record of tables: {pred1: [[..]; ..], pred2: [[..]; ..]} -> facts per predicate
/// - List/table or stream of records: first column of each row is the predicate name,
///   remaining columns are the fact terms. This allows mixing predicates in one stream.
fn collect_facts(
    input: PipelineData,
    span: Span,
) -> Result<HashMap<String, Vec<Vec<AnyDataValue>>>, LabeledError> {
    let mut facts = HashMap::new();

    match input {
        PipelineData::Empty => Ok(facts),
        PipelineData::Value(value, _) => match value {
            Value::Record { val, .. } => {
                for (pred_name, table_val) in val.iter() {
                    let rows = table_to_rows(table_val, span, pred_name)?;
                    facts.entry(pred_name.clone()).or_default().extend(rows);
                }
                Ok(facts)
            }
            Value::List { .. } => {
                let list = value.as_list().map_err(|_| {
                    LabeledError::new("expected list")
                        .with_label("pipeline input must be a list of records", value.span())
                })?;
                for row_val in list {
                    let (pred_name, row) = row_to_fact(row_val, span)?;
                    facts.entry(pred_name).or_default().push(row);
                }
                Ok(facts)
            }
            _ => Err(LabeledError::new("invalid pipeline input").with_label(
                "expected a record of tables, a list of records, or nothing",
                value.span(),
            )),
        },
        PipelineData::ListStream(stream, _) => {
            for row_val in stream {
                let (pred_name, row) = row_to_fact(&row_val, span)?;
                facts.entry(pred_name).or_default().push(row);
            }
            Ok(facts)
        }
        _ => Err(LabeledError::new("unsupported pipeline input").with_label(
            "expected a record of tables, a list of records, or nothing",
            span,
        )),
    }
}

/// Convert a single Nushell record into (predicate_name, fact_terms).
///
/// The first column is interpreted as the predicate name (must be a string).
/// All remaining columns become fact terms.
fn row_to_fact(value: &Value, _span: Span) -> Result<(String, Vec<AnyDataValue>), LabeledError> {
    let record = value.as_record().map_err(|_| {
        LabeledError::new("expected record row in pipeline input")
            .with_label("each element must be a record", value.span())
    })?;

    if record.is_empty() {
        return Err(
            LabeledError::new("empty record in pipeline input").with_label(
                "each row must have at least a predicate column",
                value.span(),
            ),
        );
    }

    let mut iter = record.iter();
    let (pred_col, pred_val) = iter.next().expect("record is non-empty");

    let pred_name = pred_val.as_str().map_err(|_| {
        LabeledError::new("predicate name must be a string").with_label(
            format!("the first column ('{pred_col}') must contain a string predicate name"),
            value.span(),
        )
    })?;

    let mut row = Vec::new();
    for (_col_name, col_val) in iter {
        match nu_value_to_nemo(col_val)? {
            Some(dv) => row.push(dv),
            None => {
                // Nothing values are skipped
            }
        }
    }

    Ok((pred_name.to_string(), row))
}

/// Convert a Nushell table value into Vec<Vec<AnyDataValue>>.
///
/// All columns are treated as fact terms (no predicate column).
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
                    // Nothing values are skipped
                }
            }
        }
        rows.push(row);
    }
    Ok(rows)
}
