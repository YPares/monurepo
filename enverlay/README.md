# enverlay

Provides a `direnv` integration for Nushell, with either automatic loading
(whenever your `CWD` changes) or through a keyboard shortcut.

Show information about your current `direnv` status and your nushell overlays
in your prompt.

Minimal setup to add to your `config.nu`:

```nushell
## In your ~/.config/nushell/config.nu

use path/to/enverlay

$env.PROMPT_COMMAND_RIGHT = {||
  $"...(enverlay render)..."
}

# Toggle ON auto direnv loading.
# This same command can be called later to toggle auto-loading on and off,
# and your prompt will show if auto-load is enabled.
enverlay auto

# Alternative: Automatically load the direnv when going INTO a folder with a .envrc file,
# but do NOT unload it when going out of it. Your env will only be replaced
# when you go to another folder with a .envrc file.
#enverlay auto --load-only

# Alternative: Use a keyboard shortcut (Alt+e by default) to load the direnv.
# This permits to control what gets loaded and when, and using a shortcut instead of
# a regular command allows to load the direnv inside a dedicated new Nushell overlay
$env.config.keybindings = [
  ...
] ++ (enverlay default-keybindings)

# Never load the FOO and BAR env vars exported by direnv:
$env.enverlay.excluded_direnv_vars ++= [FOO BAR]
```
