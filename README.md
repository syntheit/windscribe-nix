# windscribe-nix

Windscribe VPN desktop client for NixOS. Packages the official `.deb` and
ships a NixOS module that runs the helper service.

Supports x86_64-linux and aarch64-linux.

## Install

Add the flake to your inputs and enable the module:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    windscribe.url = "github:syntheit/windscribe-nix";
    windscribe.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, windscribe, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        windscribe.nixosModules.default
        {
          nixpkgs.overlays = [ windscribe.overlays.default ];
          services.windscribe.enable = true;
        }
        ./configuration.nix
      ];
    };
  };
}
```

Rebuild, then start `windscribe` from your app launcher or a terminal.
`windscribe-cli` is also available.

## What the module does

- Runs `windscribe-helper.service` as root (it manages the firewall, routes
  and tunnels).
- Bind-mounts the package to `/opt/windscribe` for the helper, since the
  helper only accepts binaries under that path.
- Installs setgid `windscribe` wrappers for the GUI and CLI so they can talk to
  the helper socket.
- Enables `programs.nix-ld`, which the bundled Go binaries need.
- Creates the `windscribe` user/group and the dirs under `/etc`, `/var/log`
  and `/var/tmp` that the app expects.

## Updating

In-app updates are disabled. To get a new version, update the flake input:

```sh
nix flake update windscribe
sudo nixos-rebuild switch
```

## Development

```sh
nix build .#windscribe                  # build the package
nix build .#checks.x86_64-linux.windscribe   # run the NixOS VM test (needs KVM)
```

To bump the version, change `version` and both hashes in `package.nix`. You
can get the hashes with:

```sh
nix store prefetch-file https://github.com/Windscribe/Desktop-App/releases/download/vX.Y.Z/windscribe_X.Y.Z_amd64.deb
nix store prefetch-file https://github.com/Windscribe/Desktop-App/releases/download/vX.Y.Z/windscribe_X.Y.Z_arm64.deb
```
