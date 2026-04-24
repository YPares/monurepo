use nemo::datavalues::{AnyDataValue, DataValue};
use nu_protocol::{LabeledError, Record, Span, Value};

/// Convert a Nushell Value to a Nemo AnyDataValue.
///
/// Maps:
/// - Int(i64)   -> AnyDataValue::new_integer_from_i64
/// - Float(f64) -> AnyDataValue::new_double_from_f64
/// - String(s)  -> AnyDataValue::new_plain_string
/// - Bool(b)    -> AnyDataValue::new_boolean
/// - Nothing    -> skipped (returns None)
///
/// Any other variant returns an error.
pub fn nu_value_to_nemo(value: &Value) -> Result<Option<AnyDataValue>, LabeledError> {
    let result = match value {
        Value::Int { val, .. } => Some(AnyDataValue::new_integer_from_i64(*val)),
        Value::Float { val, .. } => match AnyDataValue::new_double_from_f64(*val) {
            Ok(dv) => Some(dv),
            Err(e) => {
                return Err(LabeledError::new(format!(
                    "cannot convert float {val} to Nemo data value: {e}"
                )))
            }
        },
        Value::String { val, .. } => Some(AnyDataValue::new_plain_string(val.clone())),
        Value::Bool { val, .. } => Some(AnyDataValue::new_boolean(*val)),
        Value::Nothing { .. } => None,
        other => {
            return Err(LabeledError::new(format!(
                "unsupported Nushell value type: {other:?}"
            )))
        }
    };
    Ok(result)
}

/// Convert a Nemo AnyDataValue back to a Nushell Value.
///
/// Reverses value_to_datavalue. Unmappable types (IRIs, language-tagged strings, etc.)
/// become plain strings via their Display/lexical form.
pub fn nemo_value_to_nu(dv: &AnyDataValue, span: Span) -> Value {
    use nemo::datavalues::ValueDomain;

    match dv.value_domain() {
        ValueDomain::Long
        | ValueDomain::Int
        | ValueDomain::NonNegativeInt
        | ValueDomain::NonNegativeLong => Value::int(dv.to_i64_unchecked(), span),
        ValueDomain::UnsignedLong | ValueDomain::UnsignedInt => {
            // Nushell only has i64, so cast if possible
            if dv.fits_into_i64() {
                Value::int(dv.to_i64_unchecked(), span)
            } else {
                Value::string(dv.to_string(), span)
            }
        }
        ValueDomain::Double | ValueDomain::Float => Value::float(dv.to_f64_unchecked(), span),
        ValueDomain::Boolean => Value::bool(dv.to_boolean_unchecked(), span),
        ValueDomain::PlainString => Value::string(dv.to_plain_string_unchecked(), span),
        // Fallback: IRI, language-tagged string, null, tuple, map, Other -> string
        _ => Value::string(dv.to_string(), span),
    }
}

/// Convert a row of AnyDataValues into a Nushell record with columns col0, col1, ...
pub fn fact_row_to_record(row: Vec<AnyDataValue>, span: Span) -> Value {
    let mut record = Record::new();
    for (i, val) in row.iter().enumerate() {
        let col_name = format!("col{i}");
        record.push(col_name, nemo_value_to_nu(val, span));
    }
    Value::record(record, span)
}
