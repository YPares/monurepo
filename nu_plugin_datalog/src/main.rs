use nu_plugin::{MsgPackSerializer, serve_plugin};

mod commands;
mod plugin;
mod state;

use plugin::DatalogPlugin;

fn main() {
    serve_plugin(&DatalogPlugin::new(), MsgPackSerializer)
}
