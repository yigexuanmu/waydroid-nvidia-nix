[中文](README.md) — Chinese version

# waydroid-nvidia-nix

**GPU-accelerated Waydroid on NVIDIA, container-native, no VM. A self-contained
fork with the full upstream source vendored into this repo.**

[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

This repository is a self-contained fork of
[Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)
(the `Neo` branch): upstream source, patches and build scripts are all vendored
in-repo, plus PR
[#4](https://github.com/Shiro836/waydroid-nvidia/pull/4)
is merged (new XBGR2101010 / NV12 / P010 gralloc formats and an ETC2 hardware
feature probe). It is exposed as a Nix flake with 5 packages, an overlay and a
NixOS module, and every component builds directly from the in-repo source.

```
Android app ── Vulkan ──▶ guest Mesa Venus ── unix socket ──▶ host renderer
                                                                   │
KWin ◀── hwcomposer ◀── gralloc imports ◀── NVIDIA dmabufs ◀── NVIDIA driver
```

Buffers are allocated host-side as NVIDIA block-linear images and reach the
compositor as native NVIDIA dmabufs. GL runs through ANGLE, ASTC textures are
emulated in a compute shader, and frame sync is fully GPU-side.

## Prerequisites

- **NVIDIA open kernel modules** (`nvidia-open`/`nvidia-open-dkms`) — Turing
  (RTX 20 / GTX 16) or newer
- Driver **595.71+** (610.x recommended) with `nvidia-drm.modeset=1`
- A Wayland session (tested on KWin / Plasma 6)
- Kernel `binder` and `udmabuf` modules

## Quick Start

### 1. Add the flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    waydroid-nvidia-nix = {
      url = "github:yigexuanmu/waydroid-nvidia-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### 2. Enable the module

```nix
{
  inputs,
  ...
}: {
  imports = [
    inputs.waydroid-nvidia-nix.nixosModules.waydroid-nvidia
  ];

  services.waydroid-nvidia.enable = true;
  services.waydroid-nvidia.refreshRate = 144; # your monitor's refresh rate
}
```

`services.waydroid-nvidia.package` defaults to the flake's `waydroid-nvidia-full`;
no need to set it manually.

### 3. Deploy

```sh
sudo nixos-rebuild switch --flake .#myhost
```

### 4. Initialize and start

```sh
sudo waydroid init                     # download an Android image
sudo waydroid-nvidia-setup --refresh 144   # --refresh to match your monitor
systemctl --user enable --now wd-venus.service
nohup waydroid session start &>/dev/null &
```

### 5. Verify GPU acceleration

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

Expected output example:

```
GLES: Google Inc. (NVIDIA), ANGLE (NVIDIA, Vulkan 1.3.341 (NVIDIA Virtio-GPU Venus (NVIDIA GeForce RTX 4060 Ti) (0x00002788)), venus-26.0.65.35), OpenGL ES 3.2 (ANGLE 2.1.1 git hash: c1a25085dd9e)
```

## ARM Translation (run ARM apps on x86)

Waydroid on x86 only runs x86 APKs by default. Install an ARM translation layer
to run ARM apps.

**AMD CPU → use libndk. Intel CPU → use libhoudini.**

```sh
cd ~
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
nix-shell -p lzip --run "sudo venv/bin/python3 main.py install libndk"
```

Restart the container:

```sh
sudo systemctl restart waydroid-container
```

Verify:

```sh
echo "getprop ro.product.cpu.abilist" | sudo waydroid shell
# Should include arm64-v8a, armeabi-v7a
```

## Package Overview

| `nix build .#<attr>` | Description |
|----------------------|-------------|
| `virglrenderer-nvidia` | Host Venus render server (built from source with NVIDIA patches + PR#4 formats) |
| `waydroid-nvidia` | Patched Waydroid Python tools (built from source) |
| `guest-nvidia` | Guest Vulkan driver `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so` (CI prebuilt) |
| `guest-prebuilts-nvidia` | Guest hwcomposer + ANGLE + surfaceflinger (CI prebuilt) |
| `waydroid-nvidia-full` | All of the above + systemd units + udev rules + tmpfiles + setup script |
| `default` | Same as `waydroid-nvidia-full` |

Also usable via `overlays.default` or by referencing `packages.x86_64-linux.<attr>` directly.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Host (NixOS)                    │
│                                                  │
│  ┌─────────────────────┐   ┌──────────────────┐ │
│  │  waydroid session   │   │  wd-venus        │ │
│  │  (Python)           │   │  virgl_test_server│ │
│  └────────┬────────────┘   │  ┌──────────────┐│ │
│           │ binder         │  │virgl_render  ││ │
│           ▼                │  │_server       ││ │
│  ┌─────────────────────┐   │  │  dlopen()    ││ │
│  │  LXC container      │   │  │ libvulkan.so ││ │
│  │  (Android 13)       │   │  └──────┬───────┘│ │
│  │  ┌───────────────┐  │   └─────────┼─────────┘ │
│  │  │ SurfaceFlinger│  │             │ venus.sock │
│  │  │ hwcomposer    │──┼─────────────┘           │
│  │  │ libvulkan     │  │  vtest protocol          │
│  │  │ _virtio.so    │  │                         │
│  │  └───────────────┘  │                         │
│  └─────────────────────┘                         │
│              │ NVIDIA GPU (Vulkan)               │
└──────────────┼──────────────────────────────────┘
               ▼
      NVIDIA GeForce RTX
```

## Troubleshooting

**Compositor not on the NVIDIA GPU** (monitors on another GPU, iGPU-driven
laptop panel): the compositor can't display this stack's NVIDIA buffers and the
Waydroid window dies instantly. Run Waydroid nested inside `gamescope` pinned to
the NVIDIA GPU as a workaround.

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for details.

## Development

```sh
nix build .#waydroid-nvidia-full
```

Test the module locally (without deploying system-wide):

```nix
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## License

MIT (packaging layer). Upstream projects are under their respective licenses;
files under `patches/` are derivative works of their upstreams and carry those
upstreams' licenses.
