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
  name = "nypst";
  src = fs.toSource {
    root = ./..;
    fileset = ../nypst;
  };
  path = with pkgs; [
    "${typst}/bin"
  ];
}
