{
  inputs,
  pkgs,
  flake,
  system,
  ...
}:
let
  fs = pkgs.lib.fileset;
  nwLib = inputs.nushellWith.lib.mkLib pkgs;
in
nwLib.makeNuLibrary {
  name = "prowser";
  src = fs.toSource {
    root = ./..;
    fileset = ../prowser;
  };
  path = with pkgs; [
    "${fzf}/bin"
  ];
  dependencies = with flake.packages.${system}; [
    rescope
  ];
}
