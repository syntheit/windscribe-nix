{
  description = "Windscribe VPN client for NixOS";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        windscribe = pkgs.callPackage ./package.nix { };
        default = pkgs.callPackage ./package.nix { };
      });

      # NixOS VM tests use KVM; keep the check on x86_64-linux only. The
      # aarch64 package still builds and runs on aarch64 hosts.
      checks.x86_64-linux.windscribe = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest {
        imports = [ ./test.nix ];
        defaults = {
          imports = [ self.nixosModules.default ];
          services.windscribe.package = self.packages.x86_64-linux.windscribe;
        };
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
