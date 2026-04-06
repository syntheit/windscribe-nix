{
  description = "Windscribe VPN client for NixOS";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        windscribe = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.windscribe;
      };

      overlays.default = final: _prev: {
        windscribe = final.callPackage ./package.nix { };
      };

      nixosModules = {
        windscribe = import ./module.nix;
        default = self.nixosModules.windscribe;
      };
    };
}
