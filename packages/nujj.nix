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
  name = "nujj";
  src = fs.toSource {
    root = ./..;
    fileset = ../nujj;
  };
  path = with pkgs; [
    "${jujutsu}/bin"
  ];
  dependencies = with flake.packages.${system}; [
    nugh
    prowser
  ];
}
