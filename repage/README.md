# repage

Conditionally record the result of the last command, and render it through
a pager via keyboard shortcuts

Minimal setup to add to your `config.nu`:

```nushell
## In your ~/.config/nushell/config.nu

use path/to/repage

$env.PROMPT_COMMAND_RIGHT = {||
  $"...(repage render-ans-summary [--truncate])..."
}

$env.config.keybindings = [
  ...
] ++ (repage default-keybindings)
```

## Dependencies

- `less` at a version >=600 (the `--header` flag is needed)
