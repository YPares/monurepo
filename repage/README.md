# repage

Conditionally record the result of the last command, and render it through
a pager via keyboard shortcuts

Minimal setup to add to your `config.nu`:

```nushell
## In your ~/.config/nushell/config.nu

use path/to/repage

# So that we record the result of every command run in the shell
$env.config.hooks.display_output = {|| repage record-and-render}

# To print information about the recorded value in your prompt
$env.PROMPT_COMMAND_RIGHT = {||
  $"...(repage render-ans-summary --truncate)..."
}

# To open the recorded result via a selection of viewers
$env.config.keybindings = [
  ...
] ++ (repage default-keybindings)
```

See the `export-env` block at the beginning of [mod.nu](./mod.nu) for more
information about how to customize repage's behaviour.

## Dependencies

- `less` at a version >=600 (the `--header` flag is needed)
