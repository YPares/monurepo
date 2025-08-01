# monurepo

A collection of Nushell libraries and tools:

- [rescope](./rescope): scoped resources and deferred execution
- [prowser](./prowser): a prompt-based file browser, based on `std dirs` and
  `fzf`
- [enverlay](./enverlay): a tunable `direnv` integration, and a prompt that
  shows your current env and Nushell overlays
- [repage](./repage): record the result of the last command, show info about it
  in the prompt and re-render it in detail in a pager
- [deepformat](./deepformat): render nested Nushell tables and records as HTML
- [nupg](./nupg): nushell interface for PostgreSQL, with automatic conversions
  to Nushell types and query autocompletion
- [nugh](./nugh): nushell wrappers for the
  [github CLI](https://github.com/cli/cli) tool
- [nujj](./nujj): nushell wrappers for
  [`jj` (Jujutsu)](https://github.com/jj-vcs/jj)
- [jjiles](./jjiles): a jj _Watcher_: an interactive `jj log` with `fzf` (à la
  [`jj-fzf`](https://github.com/tim-janik/jj-fzf)), with custom jj log templates
  support, auto-refresh, adaptive diff layout, system theme detection (which
  will also work in [WSL](https://learn.microsoft.com/en-us/windows/wsl/)) and
  syntax-highlighting via [`delta`](https://github.com/dandavison/delta)
- [nypst](./nypst): Generate `Typst` code programmatically with Nu code

The reason to collect them all here is because Nushell currently does not have a
default package manager, and some of these libraries depend on one another.

## Using it

### Via `git clone`

Clone the repo, and add to your `config.nu`:

```nushell
const NU_LIB_DIRS = ["path/to/monurepo/clone"] ++ $NU_LIB_DIRS
```

You can now `use` any of the libraries here. **However**, you will need to
install separately all the dependencies of each library you want to use, through
your usual package manager. See each lib's own README.md file.

### Via a `nix` profile

You can install libraries from `monurepo` into a dedicated nix profile. If you
activated flakes:

```sh
nix profile add github:YPares/monurepo#nupg --profile ~/.nu-nix-profile
nix profile add github:YPares/monurepo#repage --profile ~/.nu-nix-profile
...
```

(NOTE: "`add`" was called "`install`" in older Nix versions, keep it in mind if
an error pops up saying that "`add`" command does not exist)

Then add to your `config.nu`:

```nushell
const NU_LIB_DIRS = ["~/.nu-nix-profile"] ++ $NU_LIB_DIRS
```

The advantages are:

- external dependencies for each lib come along for free, thanks to Nix
- you can update everything that is installed in the profile at once:
  `nix profile upgrade --profile ~/.nu-nix-profile --all`

### Via a custom flake using `nushellWith`

See [nushellWith](https://github.com/YPares/nushellWith).

