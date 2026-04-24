use nu_plugin::{serve_plugin, MsgPackSerializer};

mod commands;
mod conversion;
mod plugin;
mod rules_source;
mod state;

use plugin::DatalogPlugin;

fn main() {
    serve_plugin(&DatalogPlugin::new(), MsgPackSerializer)
}
