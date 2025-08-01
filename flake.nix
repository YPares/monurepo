{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    blueprint = {
      url = "github:numtide/blueprint";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nushellWith.url = "github:YPares/nushellWith";
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
