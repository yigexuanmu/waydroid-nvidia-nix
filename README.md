# waydroid-nvidia-nix

**Waydroid with full NVIDIA GPU acceleration — Nix packaging.**

All sources reference upstream; nothing is vendored in this repo.

- Packages: `github:Shiro836/waydroid-nvidia` patches + prebuilts
- NixOS module: systemd services, udev rules, tmpfiles

## Requirements

- **NVIDIA open kernel modules** (`nvidia-open`) with `nvidia-drm.modeset=1`
- NVIDIA userspace (`nvidia-utils`), driver ≥ 610.x recommended
- A Wayland session (tested on KWin / Plasma 6, Niri)
- `binder` Linux kernel module (for Waydroid)

## Installation

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    waydroid-nvidia-nix = {
      url = "github:yigexuanmu/waydroid-nvidia-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, waydroid-nvidia-nix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        waydroid-nvidia-nix.nixosModules.waydroid-nvidia
        {
          services.waydroid-nvidia.enable = true;
          # match your monitor's refresh rate (optional, > 240 Hz needs patched SF)
          services.waydroid-nvidia.refreshRate = 144;
        }
      ];
    };
  };
}
```

Then rebuild:

```sh
sudo nixos-rebuild switch --flake .#myhost
```

This installs:

| Component | Source |
|-----------|--------|
| `waydroid` (patched Python tools) | Built from `github:waydroid/waydroid` + NVIDIA patch |
| `virgl_test_server` + `virgl_render_server` | Built from `gitlab.freedesktop.org/virgl/virglrenderer` + 4 patches |
| Guest Vulkan driver (`libvulkan_virtio.so`) | CI-built artifact from `Shiro836/waydroid-nvidia` |
| Guest gralloc (`libgbm_mesa_wrapper.so`) | CI-built artifact |
| Guest display HAL + ANGLE + surfaceflinger | CI-built prebuilts |

## Post-install

1. **Download an Android image** (as usual):

   ```sh
   sudo waydroid init
   ```

2. **Provision the NVIDIA stack** (copies guest files into `/var/lib/waydroid`, writes properties):

   ```sh
   sudo waydroid-nvidia-setup --refresh 144
   ```

3. **Log out and back in** (so the `uaccess` udev rule for `/dev/udmabuf` takes effect).

4. **Start the stack**:

   ```sh
   sudo systemctl enable --now waydroid-container.service
   systemctl --user enable --now wd-venus.service
   waydroid session start
   ```

5. **Verify GPU acceleration**:

   ```sh
   sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
   # GLES: ... ANGLE (NVIDIA, Vulkan ... Venus (NVIDIA GeForce ...))
   ```

## Packages

| `nix build .#<attr>` | Description |
|----------------------|-------------|
| `virglrenderer-nvidia` | Host Venus render server (built from source) |
| `waydroid-nvidia` | Patched Waydroid Python tools (built from source) |
| `guest-nvidia` | Guest Vulkan driver + gralloc backend (prebuilt) |
| `guest-prebuilts-nvidia` | Guest hwcomposer + ANGLE + surfaceflinger (prebuilt) |
| `waydroid-nvidia-full` | Aggregate of all above + integration files |
| `default` | Same as `waydroid-nvidia-full` |

## Credits

All patches and prebuilt artifacts come from [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia). This repo only provides the Nix packaging layer.

## License

MIT (packaging layer). The upstream project is MIT; patches are MIT; prebuilt artifacts contain components under their own licenses (MIT, GPL, Apache, etc.).
