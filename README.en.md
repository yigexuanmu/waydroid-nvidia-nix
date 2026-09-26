[中文](README.md) — Chinese version

# waydroid-nvidia-nix

**GPU-accelerated Waydroid on NVIDIA, container-native, no VM. A self-contained
fork with the full upstream source vendored into this repo.**

[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

This repository is a self-contained fork of
[Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)
(the `Neo` branch): upstream source, patches and build scripts are all vendored
in-repo, plus three upstream PRs are merged —
[#4](https://github.com/Shiro836/waydroid-nvidia/pull/4) (new XBGR2101010 / NV12 /
P010 gralloc formats and an ETC2 hardware feature probe),
[#12](https://github.com/Shiro836/waydroid-nvidia/pull/12) (LINEAR-memory
screenshot banding fix) and
[#20](https://github.com/Shiro836/waydroid-nvidia/pull/20)
(hwcomposer crash fix, Scudo data-race fix, Venus socket hardening, setup
robustness, and more). It is exposed as a Nix flake with 5 packages, an overlay
and a NixOS module, and every component builds directly from the in-repo source.

```
Android app ── Vulkan ──▶ guest Mesa Venus ── unix socket ──▶ host renderer
                                                                   │
KWin ◀── hwcomposer ◀── gralloc imports ◀── NVIDIA dmabufs ◀── NVIDIA driver
```

Buffers are allocated host-side as NVIDIA block-linear images and reach the
compositor as native NVIDIA dmabufs. GL runs through ANGLE, ASTC textures are
emulated in a compute shader, and frame sync is fully GPU-side.

## Fixes over upstream

Beyond PR #4's format additions, this branch merges #12 and #20, which cover a
set of defects that actually affect day-to-day use:

| Symptom | Upstream PR | Root cause and fix |
|---------|-------------|--------------------|
| Horizontal banding in screenshots / screen recordings | [#12](https://github.com/Shiro836/waydroid-nvidia/pull/12) | CPU-mappable buffers previously landed in kernel udmabuf LINEAR memory, where NVIDIA renders corruptly. It now prefers LINEAR memory allocated by vtest itself (falling back to udmabuf for unrenderable formats) and the linear memory property is corrected from `HOST_CACHED` to `HOST_COHERENT` |
| Crashes when opening certain apps | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | hwcomposer now refuses to import `DRM_FORMAT_MOD_LINEAR` dmabufs it did not allocate itself (issue #11) |
| Sporadic Scudo crashes | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | Data race on the hwcomposer format list under concurrent read/write; guarded with `formats_mutex` |
| SystemUI crash loop | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | `waydroid-nvidia-setup` now clears the per-app `code_cache` each run (issue #13) |
| Garbled video | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | NV12 now uses a real biplanar layout (issue #16), with the uv-plane size rounded up so odd heights no longer under-allocate |
| Venus socket reachable by every local user | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | The socket moves out of the shared, root-owned, 1777 `/run/waydroid-venus` into the desktop user's private `$XDG_RUNTIME_DIR/waydroid-venus` |

**Socket location changed (read before upgrading)**: the Venus socket now lives at
`$XDG_RUNTIME_DIR/waydroid-venus/venus.sock`, created on every login by
`RuntimeDirectory=waydroid-venus` in `wd-venus.service`. The old
`/run/waydroid-venus/` is no longer used, so a hand-created directory with that
name can be deleted.

**One fixed locally (not from an upstream PR)**: P010 (10-bit HDR) had the same
bug in its CPU-fallback biplanar sizing that NV12 did — `stride * height * 3 / 2`
truncates the UV plane for odd heights (a full 4096-byte page short after
alignment, i.e. an out-of-bounds write). Fixed to the same round-up formula as
NV12, following minigbm's actual layout rule
(`drv_size_from_format() = stride * DIV_ROUND_UP(height, vertical_subsampling)`).
Even heights such as 1080p were unaffected, which is why it never showed up.

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
      url = "github:yigexuanmu/waydroid-nvidia-nix/Neo";
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

`waydroid-nvidia-setup` must be run via `sudo` **from the desktop user's own
session** (not a root login shell, and not over SSH): it needs that user's
`$XDG_RUNTIME_DIR` in order to locate the Venus socket. If the environment is
missing it exits with an error rather than guessing a path.

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
| `virglrenderer-nvidia` | Host Venus render server (built from source with NVIDIA patches, PR#4 formats, and the #12/#20 LINEAR / NV12 fixes) |
| `waydroid-nvidia` | Patched Waydroid Python tools (built from source) |
| `guest-nvidia` | Guest Vulkan driver `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so` (CI prebuilt) |
| `guest-prebuilts-nvidia` | Guest hwcomposer + ANGLE + surfaceflinger (CI prebuilt) |
| `waydroid-nvidia-full` | All of the above + systemd units + udev rules + setup script (the Venus socket directory is created automatically by `RuntimeDirectory=`, no tmpfiles unit needed) |
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

Check the packaged result (no system-wide deploy needed):

```sh
P=$(nix eval --impure --raw .#packages.x86_64-linux.waydroid-nvidia-full)
grep -E 'RuntimeDirectory=|socket-path' $P/share/systemd/user/wd-venus.service
```

You should see `RuntimeDirectory=waydroid-venus` and
`--socket-path %t/waydroid-venus/venus.sock`. The two must agree, and must
point at the same location as the `nvidia_venus_socket` value that
`waydroid-nvidia-setup` writes into `waydroid.cfg`.

Test the module locally (without deploying system-wide):

```nix
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## License

MIT (packaging layer). Upstream projects are under their respective licenses;
files under `patches/` are derivative works of their upstreams and carry those
upstreams' licenses.
