{
  description = "Nix packages for waydroid-nvidia — GPU-accelerated Waydroid on NVIDIA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          callPackage = pkgs.callPackage;
        in
        rec {
          virglrenderer-nvidia = callPackage ./pkgs/virglrenderer-nvidia { };

          waydroid-nvidia = callPackage ./pkgs/waydroid-nvidia { };

          guest-nvidia = callPackage ./pkgs/guest-nvidia { };

          guest-prebuilts-nvidia = callPackage ./pkgs/guest-prebuilts-nvidia { };

          waydroid-nvidia-full = callPackage ./pkgs/waydroid-nvidia-full {
            inherit
              virglrenderer-nvidia
              waydroid-nvidia
              guest-nvidia
              guest-prebuilts-nvidia
              ;
          };

          default = waydroid-nvidia-full;
        });

      overlays.default = final: prev: {
        virglrenderer-nvidia = final.callPackage ./pkgs/virglrenderer-nvidia { };
        waydroid-nvidia = final.callPackage ./pkgs/waydroid-nvidia { };
        guest-nvidia = final.callPackage ./pkgs/guest-nvidia { };
        guest-prebuilts-nvidia = final.callPackage ./pkgs/guest-prebuilts-nvidia { };
        waydroid-nvidia-full = final.callPackage ./pkgs/waydroid-nvidia-full {
          virglrenderer-nvidia = final.virglrenderer-nvidia;
          waydroid-nvidia = final.waydroid-nvidia;
          guest-nvidia = final.guest-nvidia;
          guest-prebuilts-nvidia = final.guest-prebuilts-nvidia;
        };
      };

      nixosModules = {
        waydroid-nvidia = import ./modules/nixos/waydroid-nvidia.nix;
      };
    };
}
