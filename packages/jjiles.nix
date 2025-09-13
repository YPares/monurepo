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
  name = "jjiles";
  src = fs.toSource {
    root = ./..;
    fileset = ../jjiles;
  };
  path = with pkgs; [
    "${jujutsu}/bin"
    "${delta}/bin"
    "${fzf}/bin"
    "${gawk}/bin"
  ];
  dependencies = with flake.packages.${system}; [
    nujj
  ];
}
