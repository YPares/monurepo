# CLAUDE.md

This file provides guidance to AI agents when working with code in this repository.

## Repository Overview

This is a **monorepo** of Nushell libraries and tools. Each subdirectory is an independent Nushell library with its own `mod.nu` entry point. Refer to the [README](./README.md) for more info about each library.

Libraries have internal dependencies (e.g., `jjiles` depends on `nujj`, `nupg` depends on `repage`). These dependencies are declared in `packages/*.nix` files.

## Architecture

### Nushell Library Structure
- Each library has a **`mod.nu`** as its entry point
- Libraries export commands, functions, and sometimes environment configuration via `export-env` blocks
- Many libraries configure themselves through `$env.<library-name>` records (e.g., `$env.nujj`, `$env.prowser`)

### Nix Integration
- **`flake.nix`**: Uses `blueprint` and `nushellWith` to package libraries
- **`packages/*.nix`**: Individual library package definitions using `nushellWith.lib.makeNuLibrary`
  - Declares external dependencies (PATH additions like `psql`, `fzf`, `delta`)
  - Declares inter-library dependencies
- Users can install via `nix profile add` or use `nushellWith` to compose custom Nushell environments

### Development with Nix
- The flake provides project-specific tools via `flake.nix`
- Use `nix run nixpkgs#<package>` or `uvx`/`npx` for quick tool access
- Use `nix search nixpkgs <keyword>` to find package names

## Common Development Commands

### Using Libraries
Since this is a monorepo without a package manager, libraries are used by adding the repo root to `NU_LIB_DIRS`:

```nushell
const NU_LIB_DIRS = ["path/to/monurepo"] ++ $NU_LIB_DIRS
use nupg
use jjiles
```

Or install individual libraries into a Nix profile:

```sh
nix profile add .#nupg --profile ~/.nu-nix-profile
nix profile add .#jjiles --profile ~/.nu-nix-profile
```

### Building and Testing
There is **no centralized build/test system**. Each library is independently developed:

- **Manual testing**: Load the library in a Nushell REPL and exercise its functions
  ```nushell
  use nupg
  $env.PSQL_DB_STRING = "postgresql://user:pass@localhost/db"
  nupg select * from some_table
  ```

- **Check syntax**: Parse `.nu` files with `nu --commands 'use <lib>'`

### Nix Package Updates
To update all libraries in a Nix profile:
```sh
nix profile upgrade --profile ~/.nu-nix-profile --all
```

## Key Implementation Details

### Library Dependencies
When working on a library, check its `packages/<lib>.nix` for:
- **`path`**: External binaries it shells out to (e.g., `psql`, `fzf`, `delta`)
- **`dependencies`**: Other monorepo libraries it imports

### Environment Configuration
Libraries often read configuration from `$env.<libname>`:
- **nupg**: Reads `$env.PSQL_DB_STRING` for DB connection
- **prowser**: Configures exclusions, colors, finder height via `$env.prowser`
- **nujj**: Template and revset configuration in `$env.nujj`

When modifying these libraries, respect existing env var conventions.

### Code Style
- Commands use kebab-case naming (e.g., `nupg select`, `prowser add`)
- `export-env` blocks initialize library-specific environment state
- Libraries use `mod.nu` to export their public API
