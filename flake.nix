{
  description = "Nix packages for waydroid-nvidia — GPU-accelerated Waydroid on NVIDIA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    wnv-src = {
      url = "github:Shiro836/waydroid-nvidia/v0.1.0-rc3";
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

      nixosModules = {
        waydroid-nvidia = import ./modules/nixos/waydroid-nvidia.nix;
      };
    };
}
