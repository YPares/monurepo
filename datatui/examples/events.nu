#!/usr/bin/env -S nu --plugins "[./target/debug/nu_plugin_datatui]"

# Simple file browser example
def main [] {
  # Initialize terminal
  datatui init
  
  loop {
    # Will print at least once per second:
    datatui events --timeout 1sec | print $in
  }
  
  # Clean up terminal
  datatui terminate
}
