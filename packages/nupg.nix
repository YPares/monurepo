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
  name = "nupg";
  src = fs.toSource {
    root = ./..;
    fileset = ../nupg;
  };
  path = with pkgs; [
    "${postgresql}/bin"
    "${sql-formatter}/bin"
    "${bat}/bin"
  ];
  dependencies = with flake.packages.${system}; [
    repage
  ];
}
