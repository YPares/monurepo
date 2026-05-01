# Streaming Improvement Plan — nu_plugin_datalog

## Problem

The current implementation eagerly collects data at several points where streaming would be more efficient:

1. **`datalog export` returns an eagerly-collected record** — it builds the entire `Record` in memory and returns a single `Value`. For large result sets, the entire output must be materialized before the first row is available to downstream Nushell commands.
2. **`datalog export` uses `SimplePluginCommand`** — which forces the return type to `Value`, excluding `PipelineData::ListStream`.
3. **Nemo's `predicate_rows()` already returns `impl Iterator<Item = Vec<AnyDataValue>>`** — but we `.collect()` it into `Vec<Value>`.

`datalog reason` already uses `PluginCommand` and handles `ListStream` input correctly — no changes needed there. Fact collection in `reason.rs` is inherently eager (all facts must be injected before program creation) — that stays as-is.

## Outcome

`datalog export` will produce a **`ListStream` of flat records**, each shaped like `{predicate: "ancestor", col0: "alice", col1: "bob"}`. This is the same format that `datalog reason` already accepts as input (list/table or stream with predicate in first column), making round-tripping natural.

The previous record-of-tables output shape `{pred1: [[..]], pred2: [[..]]}` is **removed** — no backwards compatibility needed.

## Changes

### 1. Convert `datalog export` from `SimplePluginCommand` to `PluginCommand`

**File: `src/commands/export.rs`**

`SimplePluginCommand::run` signature is `fn run(&self, plugin, engine, call, input: &Value) -> Result<Value, LabeledError>`.  
`PluginCommand::run` signature is `fn run(&self, plugin, engine, call, input: PipelineData) -> Result<PipelineData, LabeledError>`.

We need `PluginCommand` to return `PipelineData::ListStream`.

The input is still just a `DatalogState` custom value — we extract it from `PipelineData` the same way `reason.rs` does (via `input.into_value()` or by matching on `PipelineData::Value`).

**Implementation sketch:**

```rust
impl PluginCommand for Export {
    type Plugin = DatalogPlugin;

    fn name(&self) -> &str { "datalog export" }
    fn description(&self) -> &str { "Export derived facts from a datalog-state handle as a stream of records." }
    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .rest("predicates", SyntaxShape::String, "Predicate names to export")
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
        let custom = value.as_custom_value()?;
        let state = custom.as_any().downcast_ref::<DatalogState>().ok_or_else(|| ...)?;

        // ... resolve predicates_to_export (same logic as current) ...

        // Collect rows per predicate, then stream them out
        let span = call.head;
        let all_rows = collect_all_predicate_rows(plugin, state.engine_id, &predicates_to_export, &rt, span)?;

        let iter = all_rows.into_iter().flat_map(|(pred_name, rows)| {
            rows.into_iter().map(move |row| {
                fact_row_to_flat_record(&pred_name, row, span)
            })
        });

        Ok(ListStream::new(iter, span, engine_interface.signals().clone()).into())
    }
}
```

### 2. Per-predicate row collection helper

**File: `src/commands/export.rs`**

Nemo's `predicate_rows(&mut self, &Tag)` returns `Result<Option<impl Iterator<Item = Vec<AnyDataValue>> + '_>, Error>`. The `'_` lifetime borrows `&mut self`, so the iterator cannot escape the `with_engine` closure. We must collect per-predicate.

**Implementation:**

```rust
fn collect_predicate_rows(
    exec_engine: &mut nemo::api::Engine,
    rt: &tokio::runtime::Runtime,
    pred_name: &str,
    span: Span,
) -> Result<Vec<Vec<AnyDataValue>>, LabeledError> {
    let tag = Tag::new(pred_name.to_string());
    let rows_opt = rt.block_on(exec_engine.predicate_rows(&tag))
        .map_err(|e| LabeledError::new(format!("export failed for '{pred_name}': {e}")))?;
    Ok(rows_opt.map(|rows| rows.collect()).unwrap_or_default())
}
```

### 3. Add `fact_row_to_flat_record` to `conversion.rs`

**File: `src/conversion.rs`**

New function alongside the existing `fact_row_to_record`. The flat record format has the predicate name as the first column, matching the input convention for `datalog reason`.

**Implementation:**

```rust
/// Convert a predicate name and a row of AnyDataValues into a Nushell record
/// shaped as `{predicate: <name>, col0: <val>, col1: <val>, ...}`.
pub fn fact_row_to_flat_record(pred_name: &str, row: Vec<AnyDataValue>, span: Span) -> Value {
    let mut record = Record::new();
    record.push("predicate", Value::string(pred_name.to_string(), span));
    for (i, val) in row.iter().enumerate() {
        record.push(format!("col{i}"), nemo_value_to_nu(val, span));
    }
    Value::record(record, span)
}
```

### 4. Remove the old `fact_row_to_record` function (no longer used)

**File: `src/conversion.rs`**

The existing `fact_row_to_record` produces `{col0: ..., col1: ...}` (no predicate column) and was used to build the nested record-of-tables output. Since we no longer produce that shape, we can remove it.

Wait — actually, we should keep it around. `datalog reason`'s input processing uses `row_to_fact` which parses the flat format with predicate in the first column. The `fact_row_to_record` function is for the _output_ side. Since we're replacing it with `fact_row_to_flat_record`, `fact_row_to_record` becomes dead code. **Remove it.**

### 5. Use `engine_interface.signals()` for Ctrl+C propagation

When creating the `ListStream`, pass `engine_interface.signals().clone()` instead of `Signals::empty()`. This allows the user to interrupt a large export with Ctrl+C.

### 6. Update `init.plan.md`

Update the "Data flow: state → export → Nushell table" section in the plan to reflect the new streaming flat-record output shape, removing references to "record of tables" as the export output.

## What stays the same

- **`datalog reason`** — already uses `PluginCommand` and handles streaming input. Fact collection is inherently eager. No changes.
- **`value_to_rules_string`** — the intermediate `Vec<String>` for rules is tiny. Not worth changing.
- **`collect_facts` in `reason.rs`** — must be eager (all facts needed before program creation). No changes.
- **`datalog query` / `datalog validate`** — not yet implemented (Phase 3 per the plan). Their design should account for streaming from the start when we get to them.

## File-by-file summary

| File | Change |
|------|--------|
| `src/commands/export.rs` | Rewrite as `PluginCommand`; extract state from `PipelineData`; collect rows per-predicate then flat-stream; use `ListStream` with `engine_interface.signals()` |
| `src/conversion.rs` | Add `fact_row_to_flat_record`; remove `fact_row_to_record` (dead code) |
| `init.plan.md` | Update "Data flow: state → export" section to describe flat streaming output |

## Implementation order

1. Add `fact_row_to_flat_record` to `conversion.rs`
2. Remove `fact_row_to_record` from `conversion.rs` and its `use` in `export.rs`
3. Rewrite `export.rs`: `SimplePluginCommand` → `PluginCommand`, new streaming logic
4. Update `init.plan.md` output shape documentation
5. Build & manual test