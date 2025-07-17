# monurepo

A collection of Nushell libraries and tools:

- [rescope](./rescope): scoped resources and deferred execution
- [prowser](./prowser): a prompt-based file browser, based on `std dirs` and `fzf`
- [enverlay](./enverlay): a tunable `direnv` integration, and a prompt that shows your current env and Nushell overlays
- [repage](./repage): record the result of the last command, show info about it in the prompt and re-render it in detail in a pager
- [nugh](./nugh): nushell wrappers for the [github CLI](https://github.com/cli/cli) tool
- [nupg](./nupg): nushell wrappers for psql
- [nujj](./nujj): nushell wrappers for [`jj` (Jujutsu)](https://github.com/jj-vcs/jj)
- [jjiles](./jjiles): a jj _Watcher_: an interactive `jj log` with `fzf` (à la [`jj-fzf`](https://github.com/tim-janik/jj-fzf)),
  with custom jj log templates support, auto-refresh, adaptive diff layout, system theme detection
  (which will also work in [WSL](https://learn.microsoft.com/en-us/windows/wsl/))
  and syntax-highlighting via [`delta`](https://github.com/dandavison/delta)

The reason to collect them all here is because Nushell currently does not have a default package manager,
and some of these libraries depend on one another.

