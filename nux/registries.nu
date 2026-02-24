# List Nix registries
export def main [] {
  ^nix registry list | detect columns -n |
    rename registry value url |
    insert description {|x|
      let clr = match $x.registry {
        "user" => "yellow"
        "system" => "green"
        _ => "default"
      }
      [
        $"(ansi $clr)($x.value | str replace 'flake:' '')"
        $"(ansi grey)\(($x.url))"
        $"(ansi attr_italic)\(($x.registry))(ansi reset)"
      ] | str join " "
    }
}
