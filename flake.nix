{
  description = "NixOS build for haxophone";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    haxo-rs = {
      url = "github:cardonabits/haxo-rs";
      flake = false;
    };
  };

  nixConfig = {
    builders = "ssh://eu.nixbuild.net aarch64-linux - 100 1 big-parallel,benchmark";
    builders-use-substitutes = true;
  };

  outputs =
    inputs:
    with inputs;
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = nixpkgs.lib;
        overlays = [ (import rust-overlay) ];
        pkgs = import "${nixpkgs}" {
          inherit system overlays;
        };
        crossPkgs = import "${nixpkgs}" {
          inherit overlays;
          localSystem = system;
          crossSystem = "aarch64-linux";
        };
        # inference error on crate `time` caused by an API change in Rust 1.80.0
        rustVersion = pkgs.rust-bin.stable."1.79.0".default;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustVersion;
          rustc = rustVersion;
        };
      in
      rec {
        packages.haxo-rs = rustPlatform.buildRustPackage (attrs: {
          pname = "haxo-rs";
          version = haxo-rs.shortRev;
          src = haxo-rs;
          cargoLock = {
            lockFile = "${haxo-rs}/Cargo.lock";
            outputHashes = {
              "fluidsynth-0.0.1" = "sha256-1jm03ovo8gzQiGT6NdHhqyj2773c1ux1i6sw54lxPGE=";
            };
          };
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [
            alsa-lib.dev
            fluidsynth.dev
          ];
          # tests require hardware access
          doCheck = false;
          meta = {
            license = lib.licenses.mit;
            mainProgram = (builtins.fromTOML (builtins.readFile "${haxo-rs}/Cargo.toml")).package.name;
            homepage = "https://github.com/cardonabits/haxo-rs";
          };
        });

        nixosConfigurations = {
          zero2w = nixpkgs.lib.nixosSystem {
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              impermanence.nixosModules.impermanence
              ./zero2w.nix
              {
                nixpkgs.pkgs = crossPkgs; # configure cross compilation. If the build system `system` is aarch64, this will provide the aarch64 nixpkgs
              }
            ];
          };
        };

        deploy = {
          user = "root";
          nodes = {
            zero2w = {
              hostname = "zero2w";
              profiles.system.path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.zero2w;
            };
          };
        };
      }
    );
}
