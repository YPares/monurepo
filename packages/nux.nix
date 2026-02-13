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
  name = "nux";
  src = fs.toSource {
    root = ./..;
    fileset = ../nux;
  };
}
