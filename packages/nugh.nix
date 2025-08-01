{
  inputs,
  pkgs,
  ...
}:
let
  fs = pkgs.lib.fileset;
  nwLib = inputs.nushellWith.lib.mkLib pkgs;
in
nwLib.makeNuLibrary {
  name = "nugh";
  src = fs.toSource {
    root = ./..;
    fileset = ../nugh;
  };
  path = with pkgs; [
    "${gh}/bin"
  ];
}
