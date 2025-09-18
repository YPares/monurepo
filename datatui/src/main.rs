mod commands;
mod plugin;
mod terminal;
mod widgets;

use nu_plugin::{serve_plugin, MsgPackSerializer};
use plugin::DatatuiPlugin;

fn main() {
    serve_plugin(&DatatuiPlugin::default(), MsgPackSerializer);
}