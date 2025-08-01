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
  name = "repage";
  src = fs.toSource {
    root = ./..;
    fileset = ../repage;
  };
  path = with pkgs; [
    "${less}/bin"
    "${fx}/bin"
    "${tabiew}/bin"
  ];
}
