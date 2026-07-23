{
  description = "Nix packages for waydroid-nvidia — GPU-accelerated Waydroid on NVIDIA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    wnv-src = {
      url = "github:Shiro836/waydroid-nvidia/v0.1.1";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, wnv-src, ... }:
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
          virglrenderer-nvidia = callPackage ./pkgs/virglrenderer-nvidia {
            inherit wnv-src;
          };

          waydroid-nvidia = callPackage ./pkgs/waydroid-nvidia {
            inherit wnv-src;
          };

          guest-nvidia = callPackage ./pkgs/guest-nvidia { };

          guest-prebuilts-nvidia = callPackage ./pkgs/guest-prebuilts-nvidia { };

          waydroid-nvidia-full = callPackage ./pkgs/waydroid-nvidia-full {
            inherit
              wnv-src
              virglrenderer-nvidia
              waydroid-nvidia
              guest-nvidia
              guest-prebuilts-nvidia
              ;
          };

          default = waydroid-nvidia-full;
        });

      overlays.default = final: prev: {
        virglrenderer-nvidia = final.callPackage ./pkgs/virglrenderer-nvidia { inherit wnv-src; };
        waydroid-nvidia = final.callPackage ./pkgs/waydroid-nvidia { inherit wnv-src; };
        guest-nvidia = final.callPackage ./pkgs/guest-nvidia { };
        guest-prebuilts-nvidia = final.callPackage ./pkgs/guest-prebuilts-nvidia { };
        waydroid-nvidia-full = final.callPackage ./pkgs/waydroid-nvidia-full {
          inherit wnv-src;
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
