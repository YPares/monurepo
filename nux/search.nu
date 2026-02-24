use registries.nu

# Search through packages in a nix flake
export def main [
  query: string = ""
  --flake (-f): string@registries = "nixpkgs"
  --offline (-o)
] {
  (
    ^nix search --quiet --quiet
      $flake $query --json
      ...(if $offline {[--offline]} else {[]})
  ) |
    from json |
    transpose attr data |
    flatten data |
    update attr {
      split row "." | skip 2 | str join "."
    }
}
