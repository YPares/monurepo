# monurepo

A collection of Nushell libraries and tools:

- [rescope](./rescope/README.md): scoped resources and deferred execution for Nushell
- [prowser](./prowser/README.md): a prompt-based file browser, based on `std dirs` and `fzf`
- [enverlay](./enverlay/README.md): a tunable `direnv` integration, and a prompt that shows your current env and Nushell overlays
- [nujj](./nujj/README.md): nushell wrappers for [`jj` (Jujutsu)](https://github.com/jj-vcs/jj)
- [nugh](./nugh/README.md): nushell wrappers for the [github CLI](https://github.com/cli/cli) tool
- [jjiles](./jjiles/README.md): a jj _Watcher_: an interactive `jj log` with `fzf` (à la [`jj-fzf`](https://github.com/tim-janik/jj-fzf)),
  with custom jj log templates support, auto-refresh, adaptive diff layout, system theme detection
  (which will also work in [WSL](https://learn.microsoft.com/en-us/windows/wsl/))
  and syntax-highlighting via [`delta`](https://github.com/dandavison/delta)

The reason to collect them all here is because Nushell currently does not have a default package manager,
and some of these libraries depend on one another.

