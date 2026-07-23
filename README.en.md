[中文](README.md) — 阅读中文版本

# waydroid-nvidia-nix

**GPU-accelerated Waydroid on NVIDIA**, packaged as Nix packages and a NixOS module.

All components reference upstream sources — no vendoring.

- Host (virglrenderer) and Waydroid Python tools are built from source
- Guest Android components (Vulkan driver, hwcomposer, ANGLE, surfaceflinger) are fetched from CI release tarballs

## Prerequisites

- NVIDIA open kernel module (`nvidia-open`) with `nvidia-drm.modeset=1`
- NVIDIA userspace driver `nvidia-utils` (≥ 610.x recommended)
- Wayland session
- `binder` Linux kernel module (required by Waydroid)
- `udmabuf` kernel module (required by virgl Venus)

## Quick Start

### 1. Add flake input

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

Waydroid-nvidia config is usually kept in a separate file, e.g. `configuration/modules/services/waydroid-nvidia.nix`:

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
  services.waydroid-nvidia.package = inputs.waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full;
}
```

Or inline it directly in `flake.nix`:

```nix
modules = [
  waydroid-nvidia-nix.nixosModules.waydroid-nvidia
  {
    services.waydroid-nvidia.enable = true;
    services.waydroid-nvidia.refreshRate = 144;
    services.waydroid-nvidia.package = waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full;
  }
];
```

If using a separate file, import it in your main modules list:

```nix
{
  outputs = { nixpkgs, ... } @ inputs: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration/modules/services/waydroid-nvidia.nix
      ];
    };
  };
}
```

Options:

| Method | Description |
|--------|-------------|
| `waydroid-nvidia-nix.nixosModules.waydroid-nvidia` | Reference the module directly; `package` defaults to the flake's package |
| `waydroid-nvidia-nix.overlays.default` | Add to `nixpkgs.overlays`, then reference from `pkgs.waydroid-nvidia-full` |
| `waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full` | Standalone package, set `package` manually in the service |

The first one is recommended.

### 3. Deploy

```sh
sudo nixos-rebuild switch --flake .#myhost
```

### 4. Initialize Android images

```sh
sudo waydroid init
```

### 5. Configure NVIDIA acceleration

```sh
sudo waydroid-nvidia-setup --refresh 144
# --refresh specifies your display refresh rate in Hz
```

### 6. Start the session

```sh
nohup waydroid session start &>/dev/null &
```

### 7. Verify GPU acceleration

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

Expected output:

```
GLES: Google Inc. (NVIDIA), ANGLE (NVIDIA, Vulkan 1.3.341 (NVIDIA Virtio-GPU Venus (NVIDIA GeForce RTX 4060 Ti) (0x00002788)), venus-26.0.65.35), OpenGL ES 3.2 (ANGLE 2.1.1 git hash: c1a25085dd9e)
```

## ARM Translation (run ARM apps on x86)

Waydroid on x86 only runs x86 APKs by default. Install an ARM translation layer to run ARM apps.

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

## Usage

| Command | Description |
|---------|-------------|
| `waydroid status` | Check container and session status |
| `waydroid show-full-ui` | Show Android desktop in a window |
| `waydroid app install path/to/app.apk` | Install an APK |
| `waydroid app launch <package>` | Launch an app (e.g. `com.android.chrome`) |
| `waydroid shell` | Open Android shell (use `echo "cmd" \| sudo waydroid shell` for one-shot commands) |
| `echo "getprop <key>" \| sudo waydroid shell` | Read Android properties |
| `sudo waydroid shell input tap x y` | Simulate touch input |
| `sudo waydroid shell input keyevent KEYCODE_BACK` | Simulate key press |

List installed packages:

```sh
echo "pm list packages" | sudo waydroid shell
```

### Restarting Waydroid

```sh
# Stop the old session
pkill -f "waydroid session"

# Restart container
sudo systemctl restart waydroid-container

# Start a new session
nohup waydroid session start &>/dev/null &
```

## Package Overview

| `nix build .#<attr>` | Description |
|----------------------|-------------|
| `virglrenderer-nvidia` | Host Venus render server (built from source with NVIDIA patches) |
| `waydroid-nvidia` | Patched Waydroid Python tools (built from source) |
| `guest-nvidia` | Guest Vulkan driver `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so` (CI prebuilt) |
| `guest-prebuilts-nvidia` | Guest hwcomposer + ANGLE + surfaceflinger (CI prebuilt) |
| `waydroid-nvidia-full` | All of the above + systemd units + udev rules + tmpfiles + setup script |
| `default` | Same as `waydroid-nvidia-full` |

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

## Development

Build locally:

```sh
nix build .#waydroid-nvidia-full
```

Test the module locally (without deploying system-wide):

```nix
# In /etc/nixos/flake.nix
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## Credits

All patches and prebuilt components are from [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia). This repository only provides the Nix packaging layer.

## License

MIT (packaging layer). Upstream projects are under their respective licenses.
