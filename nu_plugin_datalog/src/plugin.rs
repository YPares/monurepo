use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use nu_plugin::{EngineInterface, Plugin, PluginCommand};
use nu_protocol::{CustomValue, LabeledError};

use crate::state::DatalogState;

static NEXT_ENGINE_ID: AtomicU64 = AtomicU64::new(1);

thread_local! {
    static ENGINES: RefCell<HashMap<u64, nemo::api::Engine>> = RefCell::new(HashMap::new());
}

/// Datalog plugin storing Nemo engines in a thread-local map.
///
/// Nushell plugins must implement `Sync` (see
/// <https://docs.rs/nu-plugin/latest/nu_plugin/trait.Plugin.html>), and may have
/// invocations run in parallel on different threads. However, Nemo's `ExecutionEngine`
/// contains `Rc` and `RefCell` internally and is `!Send`. We store engines in a
/// `thread_local!` `RefCell<HashMap>` — each thread gets its own engine map. Since
/// `custom_value_dropped` and command `run` calls for a given engine will execute on
/// the same thread within a single plugin process, this is sufficient. If an engine
/// is created on one thread and accessed from another, the lookup will simply fail,
/// and the user gets a clear "engine not found" error.
pub struct DatalogPlugin;

impl DatalogPlugin {
    pub fn new() -> Self {
        Self
    }

    pub fn store_engine(&self, engine: nemo::api::Engine) -> DatalogState {
        let id = NEXT_ENGINE_ID.fetch_add(1, Ordering::Relaxed);
        ENGINES.with(|engines| {
            engines.borrow_mut().insert(id, engine);
        });
        DatalogState { engine_id: id }
    }

    pub fn drop_engine(&self, id: u64) {
        ENGINES.with(|engines| {
            engines.borrow_mut().remove(&id);
        });
    }

    pub fn with_engine<F, R>(&self, id: u64, f: F) -> Option<R>
    where
        F: FnOnce(&mut nemo::api::Engine) -> R,
    {
        ENGINES.with(|engines| {
            let mut engines = engines.borrow_mut();
            engines.get_mut(&id).map(f)
        })
    }
}

impl Plugin for DatalogPlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![
            Box::new(crate::commands::reason::Reason),
            Box::new(crate::commands::export::Export),
        ]
    }

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
