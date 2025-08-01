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
  name = "enverlay";
  src = fs.toSource {
    root = ./..;
    fileset = ../enverlay;
  };
  path = with pkgs; [
    "${direnv}/bin"
  ];
}
