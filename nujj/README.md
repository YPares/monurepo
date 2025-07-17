# nujj

## Main features

- `nujj tblog`: get the jj log as a structured nushell table
- `nujj atomic`: run some arbitrary nu closure that performs a set of jj operations,
  and automatically rollback to the initial state if one fails
- `nujj cap-off` / `nujj rebase-caps`: speed up your [mega-merge workflow](https://ofcr.se/jujutsu-merge-workflow)
  with automated rebases and bookmark moves driven by simple tags in your revisions descriptions
- Autocompletion: change ids, bookmark names, etc. autocompletion is provided for most of the `nujj` commands

## Dependencies

- jj (nixpkgs#jujutsu) (latest stable version preferably)
