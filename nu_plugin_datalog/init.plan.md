# nu_plugin_datalog — Plan

A Nushell plugin wrapping [Nemo](https://github.com/knowsys/nemo)'s Rust API to provide
Datalog reasoning over structured data. Ingest Nushell tables (ABox), apply rules (TBox),
query derived facts — all in memory, no temp files.

- Nemo repo: <https://github.com/knowsys/nemo>
- Nemo docs: <https://knowsys.github.io/nemo-doc/>
- Nemo rule language reference: <https://knowsys.github.io/nemo-doc/intro/tour/>
- Nushell plugin docs: <https://docs.rs/nu-plugin/latest/nu_plugin/>
- Nushell plugin example: <https://github.com/nushell/nushell/tree/main/crates/nu_plugin_example>

## Why

Nushell is a table processor. Datalog computes fixpoints over relations (tables). The data
model fits perfectly: tables in → rule-based derivation → tables out. Nemo provides a
full-featured Datalog engine with a structured Rust API that operates entirely in memory.

## Core Workflow

```
rules.rls ──→ parse ──→ Program
                                      ╲
Nushell record of tables ──→ Facts ───→ Engine ──→ execute ──→ DatalogState (handle)
                                                                      │
                                                         datalog export ──→ Nushell table(s)
```

1. `datalog reason` — load rules + data, run to fixpoint, return an opaque state handle
2. `datalog export` — take a state handle, extract facts as Nushell tables
3. The state handle can be reused: export different predicates without re-computing

## State management

Nushell plugins are long-running processes. The plugin struct persists across calls
([`Plugin` trait](https://docs.rs/nu-plugin/latest/nu_plugin/trait.Plugin.html)).
Engines are stored in the plugin's internal `HashMap<EngineId, ExecutionEngine>` behind
a `RwLock`. Commands that create an engine store it and return a handle (a `CustomValue`
containing the ID). Commands that read from an engine look it up by ID.

```rust
struct DatalogPlugin {
    engines: RwLock<HashMap<u64, ExecutionEngine>>,
}
```

The `CustomValue` returned to Nushell is just a thin wrapper around the engine ID:

```rust
struct DatalogState {
    engine_id: u64,
}
```

When serialized/deserialized through the plugin protocol, only the ID travels. The actual
engine stays in plugin memory. If a state handle references an engine that has been
dropped (e.g. plugin restarted), `datalog export` returns a clear error.

## Commands

### `datalog reason`

Load rules and data, run the Datalog engine to fixpoint. Returns an opaque state handle
that can be passed to `datalog export`.

```nushell
# Rules only — facts inline in the rules string
datalog reason --rules 'p(a,b). p(b,c). q(?X,?Z) :- p(?X,?Y), p(?Y,?Z).'

# Rules as a list of strings (dots are auto-added)
datalog reason --rules ['p(a,b)' 'p(b,c)' 'q(?X,?Z) :- p(?X,?Y), p(?Y,?Z)']

# Rules from file
datalog reason --rules-file rules.rls

# Rules from file, multiple data tables piped in as a record
{
  parent: [[col0 col1]; [alice bob] [bob carol]],
  company: [[col0]; [acme] [globex]],
} | datalog reason --rules-file rules.rls

# Pipe a plain table — first column is the predicate name
[[predicate col1 col2]; [parent alice bob] [parent bob carol] [company acme]]
| datalog reason --rules-file rules.rls
```

**Parameters:**

| Parameter       | Type     | Description                                                        |
| --------------- | -------- | ------------------------------------------------------------------ |
| `--rules`       | string or list<string> | Inline Datalog rules string, or list of rule strings (dots auto-added, exclusive with `--rules-file`, optional) |
| `--rules-file`  | filepath | Path to a `.rls` file (exclusive with `--rules`, optional)         |

`--rules` and `--rules-file` are mutually exclusive. If neither is given, the rules default to an empty string (facts-only reasoning).

**Input:** Optional. Two forms:

- **Record of tables:** keys = predicate names, values = tables of fact rows. This is the
  primary form — it maps directly to Nemo's `HashMap<Tag, SimpleTable>`.
- **List/table or stream of records:** the first column of each row is the predicate name,
  and the remaining columns are the fact terms. This allows mixing multiple predicates in a
  single streamed input without accumulating everything into a record first.

**Output:** A `datalog-state` custom value (opaque handle).

### `datalog export`

Extract facts from a previously computed engine state. Takes a state handle as pipeline
input and returns derived facts as Nushell tables.

```nushell
# Reason once, export different predicates without recomputing
let state = datalog reason --rules-file rules.rls

# Export specific predicates
$state | datalog export ancestor reachable

# Export all derived predicates
$state | datalog export --all

# Export predicates declared with @export in the rules
$state | datalog export
```

**Parameters:**

| Parameter  | Type          | Description                                                      |
| ---------- | ------------- | ---------------------------------------------------------------- |
| predicates | string...      | Positional: predicate names to export (space-separated)        |
| `--all`    | switch        | Export ALL derived predicates (IDB)                               |

If neither `predicates` nor `--all` is given, exports the predicates from `@export`
directives in the rules file
([Nemo export docs](https://knowsys.github.io/nemo-doc/reference/exports/)).

**Input:** A `datalog-state` custom value (from `datalog reason`).

**Output:** A **record of tables** keyed by predicate name, even for a single predicate.
This is consistent and avoids surprising shape changes when the user adds/removes a
predicate name from the list.

Columns are named `col0`, `col1`, ... (future: infer from `@declare` directives).

### `datalog query`

Convenience: reason + export in one shot. For quick one-liners where reusing state isn't
needed.

```nushell
datalog query --rules 'p(a,b). p(b,c). p(?X,?Z) :- p(?X,?Y), p(?Y,?Z).' "p(alice, ?X)"
```

**Parameters:**

| Parameter      | Type     | Description                                                |
| -------------- | -------- | ---------------------------------------------------------- |
| `--rules`      | string   | Inline Datalog rules (exclusive with `--rules-file`)       |
| `--rules-file` | filepath | Path to a `.rls` file (exclusive with `--rules`)           |
| query          | string   | Positional: atom pattern like `pred(val, ?X)` (required)   |

**Output:** A record of tables keyed by predicate name (e.g. `{ancestor: [...]}`).

### `datalog validate`

Validate rules without executing. Returns parse errors and warnings.

```nushell
datalog validate --rules rules.rls
datalog validate --rules-file rules.rls
```

**Output:** A table of diagnostics (severity, message, location).

## Architecture

### Crate structure

```
nu_plugin_datalog/
├── Cargo.toml
├── PLAN.md
└── src/
    ├── main.rs           # Plugin entry point: serve_plugin(...)
    ├── plugin.rs         # DatalogPlugin struct with engines HashMap
    ├── state.rs          # DatalogState CustomValue (thin handle wrapper)
    ├── commands/
    │   ├── mod.rs
    │   ├── reason.rs     # `datalog reason`
    │   ├── export.rs     # `datalog export`
    │   ├── query.rs      # `datalog query`
    │   └── validate.rs   # `datalog validate`
    ├── conversion.rs     # Nushell Value <-> Nemo AnyDataValue / Fact
    ├── engine.rs         # Thin wrapper around nemo::execution::ExecutionEngine
    └── rules_source.rs   # RulesSource enum (Inline vs File)
```

### Plugin struct (`plugin.rs`)

Uses [`Plugin::custom_value_dropped()`](https://docs.rs/nu-plugin/latest/nu_plugin/trait.Plugin.html#method.custom_value_dropped)
for automatic engine cleanup (see engine lifecycle below).

```rust
use std::collections::HashMap;
use std::sync::RwLock;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_ENGINE_ID: AtomicU64 = AtomicU64::new(1);

pub struct DatalogPlugin {
    pub engines: RwLock<HashMap<u64, ExecutionEngine>>,
}

impl DatalogPlugin {
    pub fn new() -> Self {
        Self { engines: RwLock::new(HashMap::new()) }
    }

    pub fn store_engine(&self, engine: ExecutionEngine) -> DatalogState {
        let id = NEXT_ENGINE_ID.fetch_add(1, Ordering::Relaxed);
        self.engines.write().unwrap().insert(id, engine);
        DatalogState { engine_id: id }
    }

    pub fn get_engine(&self, id: u64) -> Option<EngineRef> {
        // Returns a guard that keeps the RwLock read guard alive
    }

    pub fn drop_engine(&self, id: u64) {
        self.engines.write().unwrap().remove(&id);
    }
}

impl Plugin for DatalogPlugin {
    // ... version(), commands() ...

    fn custom_value_dropped(
        &self,
        _engine: &EngineInterface,
        custom_value: Box<dyn CustomValue>,
    ) -> Result<(), LabeledError> {
        if let Some(state) = custom_value.as_any().downcast_ref::<DatalogState>() {
            self.drop_engine(state.engine_id);
        }
        Ok(())
    }
}
```

When all copies of a `DatalogState` handle are dropped in Nushell, the engine sends a
`Dropped` notification. The plugin removes the engine from its HashMap, freeing memory.
This is automatic — no manual cleanup command needed.

**Note:** Nushell creates a new `CustomValue` each time it sends one to the plugin, so
the plugin will receive multiple `Dropped` notifications if the handle was cloned. The
second and subsequent drops for the same ID are no-ops (the HashMap entry is already gone).

### Custom value (`state.rs`)

Uses [`CustomValue::notify_plugin_on_drop()`](https://docs.rs/nu-protocol/latest/nu_protocol/trait.CustomValue.html#method.notify_plugin_on_drop)
to request drop notifications from the engine.

```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DatalogState {
    pub engine_id: u64,
}

impl CustomValue for DatalogState {
    fn clone_value(&self, span: Span) -> Value { ... }
    fn value_string(&self) -> String { format!("datalog-state({})", self.engine_id) }
    fn to_base_value(&self, span: Span) -> Value { ... }
    fn as_any(&self) -> &dyn Any { self }
    fn notify_plugin_on_drop(&self) -> bool { true }
    // type_name, typetag_name, typetag_deserialize...
}
```

`notify_plugin_on_drop()` returns `true` so that Nushell sends a `Dropped` notification
when all copies of the handle go out of scope. The plugin handles cleanup in
`Plugin::custom_value_dropped()` — see engine lifecycle below.

### Key type bridges (`conversion.rs`)

Maps between [`nu_protocol::Value`](https://docs.rs/nu-protocol/latest/nu_protocol/enum.Value.html)
and [`AnyDataValue`](https://github.com/knowsys/nemo/blob/main/nemo-physical/src/datavalues/mod.rs).

**Nushell → Nemo:**

| Nushell `Value`     | Nemo `AnyDataValue`         |
| ------------------- | --------------------------- |
| `Int(i64)`          | `AnyDataValue::from(i64)`   |
| `Float(f64)`        | `AnyDataValue::from(f64)`   |
| `String(String)`    | `AnyDataValue::from(String)`|
| `Bool(bool)`        | `AnyDataValue::from(bool)`  |
| `Nothing`           | skipped / null              |

**Nemo → Nushell:** reverse of above. `AnyDataValue` variants that don't map cleanly
(e.g. IRIs, language-tagged strings) become `String` with their lexical form.

### Rules source (`rules_source.rs`)

```rust
pub enum RulesSource {
    Inline(String),
    File(PathBuf),
}
```

Parsed from mutually exclusive `--rules` / `--rules-file` flags.

### Engine wrapper (`engine.rs`)

Thin wrapper around [`ExecutionEngine`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_engine.rs).
Uses [`load_program()`](https://github.com/knowsys/nemo/blob/main/nemo/src/api.rs) for
parsing and [`ExecutionEngine::from_program()`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_engine.rs)
for construction.

```rust
pub struct DatalogEngine {
    engine: DefaultExecutionEngine,
}

impl DatalogEngine {
    /// Load rules from source, inject facts for multiple predicates, execute
    async fn reason(
        source: RulesSource,
        facts: HashMap<String, Vec<Vec<AnyDataValue>>>,
    ) -> Result<Self>;

    /// Retrieve all rows for a predicate
    async fn predicate_rows(&mut self, predicate: &str) -> Result<Vec<Vec<AnyDataValue>>>;

    /// List all derived predicates
    fn derived_predicates(&self) -> Vec<String>;

    /// List predicates from @export directives
    fn export_predicates(&self) -> Vec<String>;

    /// Validate rules without executing
    fn validate(source: RulesSource) -> Vec<Diagnostic>;
}
```

### Data flow: pipeline input → facts

Pipeline input can be a record of tables, a list/table of records, or a stream of records.
The plugin builds a `HashMap<String, Vec<Vec<AnyDataValue>>>`:

**Record of tables** (primary form):
```nushell
{
  parent:  [[col0 col1]; [alice bob] [bob carol]],
  company: [[col0]; [acme]],
} | datalog reason --rules-file rules.rls
```
→ `{"parent": [["alice","bob"], ["bob","carol"]], "company": [["acme"]]}`

**List/table with predicate in first column:**
```nushell
[[predicate col0 col1]; [parent alice bob] [parent bob carol] [company acme]]
| datalog reason --rules-file rules.rls
```
→ `{"parent": [["alice","bob"], ["bob","carol"]], "company": [["acme"]]}`

This form also works with streamed lists, because `datalog reason` implements
`PluginCommand` and consumes `PipelineData::ListStream` row-by-row.`

The facts are injected directly into the [`Program`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/programs/program.rs) before creating the engine:

```rust
let mut program = load_program(rules_string, label)?;
for (predicate, rows) in &input_facts {
    let tag = Tag::new(predicate);
    for row in rows {
        let fact = Fact::new(
            tag.clone(),
            row.iter().cloned().map(|v| Primitive::ground(v).into()),
        );
        program.add_statement(Statement::Fact(fact));
    }
}
let engine = ExecutionEngine::from_program(program, params).await?;
```

This maps directly to how Nemo's
[`add_imports()`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_engine.rs)
works internally — it groups facts by predicate into a
`HashMap<Tag,` [`SimpleTable`](https://github.com/knowsys/nemo/blob/main/nemo-physical/src/management/database/sources.rs)`>`.
No [`ResourceProvider`](https://github.com/knowsys/nemo/blob/main/nemo/src/io/resource_providers.rs)
implementation needed.

### Data flow: state → export → Nushell table

In `datalog export`:

1. Extract `engine_id` from the `DatalogState` custom value (pipeline input)
2. Look up the engine in `plugin.engines`
3. Determine which predicates to export:
   - Positional `predicates` list → explicit
   - `--all` → all derived predicates
   - default → predicates from `@export` directives
4. For each predicate, call [`engine.predicate_rows(&tag)`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_engine.rs) → `Iterator<Item = Vec<AnyDataValue>>`
5. Convert each row to `Value::record` with columns `col0`, `col1`, ...

**Output shape:** always a **record of tables** keyed by predicate name, regardless of how
many predicates are exported:
```nushell
{ancestor: [[col0 col1]; [alice bob] [alice carol]], reachable: [[col0 col1]; [...]]}
```
Even a single predicate returns `{ancestor: [...]}` — consistent shape, no surprises when
adding/removing predicate names.

## Dependencies

```toml
[dependencies]
nu-plugin = "0.103"
nu-protocol = "0.103"
nemo = { git = "https://github.com/knowsys/nemo", branch = "main" }
tokio = { version = "1", features = ["rt", "macros"] }
serde = { version = "1", features = ["derive"] }
```

**Note:** Nemo requires **nightly Rust** (`#![feature(...)]`). This is handled naturally
by Nix — [Nemo's own `flake.nix`](https://github.com/knowsys/nemo/blob/main/flake.nix)
already configures nightly. We follow the same pattern.

## Nix packaging

Add to the monorepo's `flake.nix` using `nushellWith`. Follow
[Nemo's own `flake.nix`](https://github.com/knowsys/nemo/blob/main/flake.nix)
pattern for nightly Rust:

```nix
# packages/nu_plugin_datalog.nix
let
  rustPlatform = pkgs.rustPlatform.override { inherit (pkgs.rust-bin.nightly.latest) rustc cargo; };
in
nushellWith.lib.makeNuPlugin {
  pkgs = pkgs // {inherit rustPlatform;};
  name = "nu_plugin_datalog";
  src = ./nu_plugin_datalog;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];
  cargoLock = {
    lockFile = ./nu_plugin_datalog/Cargo.lock;
    # nemo needs nightly
  };
}
```

## Open questions

1. **Nightly Rust requirement.** Nemo uses `#![feature(iter_intersperse)]`,
   `#![feature(str_from_raw_parts)]`, `#![feature(associated_type_defaults)]`.
   Nix handles this — follow Nemo's own flake pattern. Worth tracking whether Nemo
   upstream moves to stable.

2. **Engine lifecycle.** Resolved: automatic via `Plugin::custom_value_dropped()`.
   `DatalogState::notify_plugin_on_drop()` returns `true`, Nushell sends a `Dropped`
   notification when all copies are GC'd, plugin removes the engine. Idempotent.

3. **Output shape.** Resolved: always a record of tables, even for a single predicate.

4. **Column names.** Can we extract them from `@declare` directives in the program?
   Or always use `col0`, `col1`, ...? Should the record-of-tables input preserve column
   names from the input tables and pass them through to output?

5. **Large datasets.** Nemo is in-memory. What happens when a Nushell table has millions
   of rows? Should we support streaming or warn above a threshold?

6. **Error reporting.** Nemo's [`ProgramReport`](https://github.com/knowsys/nemo/blob/main/nemo/src/error/report.rs)
   includes source locations and hints. How much of this should surface as Nushell `LabeledError` spans?

7. **Version coupling.** Nemo is v0.10.x and under heavy development. API breaks expected.
   Pin to a specific commit and update deliberately.

## Implementation phases

### Phase 1: Minimal viable plugin: DONE
- `datalog reason` with `--rules` (inline string only), no pipeline input
- Inline facts in the rules string only
- `datalog export <pred>...` with positional predicate names (space-separated)
- Store engine in plugin HashMap, return DatalogState handle
- No `--rules-file`, no `--as`, no `--all`

### Phase 2: Pipeline integration DONE
- Accept record of tables as pipeline input → facts for multiple predicates
- Accept list/table/stream where first column is the predicate name
- `--rules-file` for file paths
- `--all` flag on `datalog export`
- Convert `Value::record` or stream → `HashMap<Tag, Vec<Fact>>` → inject into `Program`
- Multiple predicates returned as record of tables (always a record, even single)

### Phase 3: Polish
- `datalog query` with pattern parsing
- `datalog validate`
- Proper error messages from `ProgramReport`
- Column name inference from `@declare`
- Nix packaging via flake

### Phase 4: Advanced
- Incremental reasoning: add facts without recomputing everything
- Tracing support (`--trace "ancestor(alice,?X)"`)
- SPARQL import passthrough

## Key Nemo source files

These are the Nemo internals that inform this plan:

- [`nemo/src/api.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/api.rs) — `load()`, `load_string()`, `load_program()`, `reason()`, `output_predicates()`
- [`nemo/src/execution/execution_engine.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_engine.rs) — `ExecutionEngine`, `from_program()`, `execute()`, `predicate_rows()`, `add_imports()`
- [`nemo/src/execution/execution_parameters.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/execution/execution_parameters.rs) — `ExecutionParameters`, `ExportParameters`, `ImportManager`
- [`nemo/src/rule_model/programs/program.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/programs/program.rs) — `Program`, `add_statement()`, `add_rule()`
- [`nemo/src/rule_model/components/fact.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/components/fact.rs) — `Fact::new()`, `Fact::parse()`
- [`nemo/src/rule_model/components/rule.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/components/rule.rs) — `Rule::new()`, head/body structure
- [`nemo/src/rule_model/components/atom.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/components/atom.rs) — `Atom::new()`, `Atom::parse()`
- [`nemo/src/rule_model/components/term/primitive.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/rule_model/components/term/primitive.rs) — `Primitive` (ground terms + variables), `From<i64>`, `From<String>`, etc.
- [`nemo-physical/src/management/database/sources.rs`](https://github.com/knowsys/nemo/blob/main/nemo-physical/src/management/database/sources.rs) — `SimpleTable`, `TableSource`
- [`nemo/src/io/resource_providers.rs`](https://github.com/knowsys/nemo/blob/main/nemo/src/io/resource_providers.rs) — `ResourceProvider` trait, `ResourceProviders`
- [`nemo-physical/src/datasources/table_providers.rs`](https://github.com/knowsys/nemo/blob/main/nemo-physical/src/datasources/table_providers.rs) — `TableProvider` trait
- [`nemo-cli/src/cli.rs`](https://github.com/knowsys/nemo/blob/main/nemo-cli/src/cli.rs) — CLI flags (`--export`, `--print-facts`, `--trace`, etc.)

## Key Nushell plugin source files

- [`nu-plugin/src/plugin/mod.rs`](https://github.com/nushell/nushell/blob/main/crates/nu-plugin/src/plugin/mod.rs) — `Plugin` trait, `custom_value_dropped()`, `serve_plugin()`
- [`nu_plugin_example/`](https://github.com/nushell/nushell/tree/main/crates/nu_plugin_example) — reference plugin implementation
- [`nu-protocol CustomValue`](https://docs.rs/nu-protocol/latest/nu_protocol/trait.CustomValue.html) — `notify_plugin_on_drop()`, `to_base_value()`, serialization
