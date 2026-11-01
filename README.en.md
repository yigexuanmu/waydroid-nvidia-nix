[中文](README.md) — 用中文阅读本文档

# waydroid-nvidia-nix

**GPU-accelerated Waydroid on NVIDIA cards**, packaged as a Nix package and a NixOS module.

The packaging follows upstream [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)
release [**v0.2.0**](https://github.com/Shiro836/waydroid-nvidia/releases/tag/v0.2.0): the patches,
release assets, installer script, udev/systemd integration and directory layout all come from that
tag. This repository vendors no code.

- The host side (virglrenderer, the patched Waydroid tools) is built from source
- The three v0.2.0 release assets (native bundle, vendor image, guest components) are fetched from
  the release and verified by sha256

## Requirements

- An **NVIDIA kernel module** with `nvidia-drm.modeset=1`
  - default mode `nvidia-prolapse`: open (`nvidia-open`) or closed kernel module; **no** host
    user-space driver needed
  - `venus`: needs the open kernel module
  - `glibc-shim`: uses your host's own NVIDIA driver (550 or newer, plus its 32-bit libraries)
- A Wayland session running on the NVIDIA GPU
- The `binder` kernel module (the module already sets `boot.kernelModules = [ "binder_linux" ]`)
- The `udmabuf` kernel module (only for the `venus` mode)

## Quick start

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

Keep the waydroid-nvidia configuration in its own file, e.g.
`configuration/modules/services/waydroid-nvidia.nix`:

```nix
{
  inputs,
  ...
}: {
  imports = [
    inputs.waydroid-nvidia-nix.nixosModules.waydroid-nvidia
  ];

  services.waydroid-nvidia.enable = true;
  services.waydroid-nvidia.package =
    inputs.waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full;

  # optional, see the table below
  # services.waydroid-nvidia.mode = "nvidia-prolapse";
  # services.waydroid-nvidia.nativeGl = "off";
  # services.waydroid-nvidia.refreshRate = 144;
}
```

Or inline in the `modules` list of your `flake.nix`:

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

If you use a separate file, import it from the main module list:

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

Module options:

| Option | Default | Meaning |
|--------|---------|---------|
| `enable` | `false` | Turn on the integration (systemd unit, udev rules, tmpfiles) |
| `package` | the flake's `waydroid-nvidia-full` | Package to use |
| `mode` | `null` | Passed to `waydroid-nvidia-setup --mode`: `nvidia-prolapse`, `glibc-shim` or `venus`. `null` keeps whatever `waydroid.cfg` says; a fresh install gets upstream's default (`nvidia-prolapse`) |
| `nativeGl` | `null` | Passed to `--native-gl on\|off`: use the mode's own GL driver instead of ANGLE. `null` keeps the current value (off on a fresh install) |
| `refreshRate` | `null` | Passed to `--refresh <hz>`: override the rate hwcomposer reports. `null` uses the fastest current mode of your outputs |

> These options only choose the flags in the printed setup command and whether the `wd-venus` user
> service runs. What actually writes `waydroid.cfg` is `sudo waydroid-nvidia-setup` (it also stages
> the images and runs the GPU gate).

Three ways to consume the flake:

| Way | Description |
|-----|-------------|
| `waydroid-nvidia-nix.nixosModules.waydroid-nvidia` | Import the module; `package` defaults to the flake's own package |
| `waydroid-nvidia-nix.overlays.default` | Add to `nixpkgs.overlays`, then use `pkgs.waydroid-nvidia-full` |
| `waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full` | Use the package alone and set the service `package` by hand |

The first one is recommended.

### 3. Deploy

```sh
sudo nixos-rebuild switch --flake .#myhost
```

### 4. Configure the NVIDIA stack

```sh
sudo waydroid-nvidia-setup
```

The setup checks your system, tests the driver on your GPU and only then installs upstream's Android
vendor image (your official vendor image is kept as a backup). On a fresh install it runs
`waydroid init` for you; for Google apps use `sudo waydroid-nvidia-setup -s GAPPS`.

Common flags:

```sh
sudo waydroid-nvidia-setup --mode venus        # switch driver mode
sudo waydroid-nvidia-setup --native-gl on      # the mode's own GL driver (nvidia-prolapse, glibc-shim)
sudo waydroid-nvidia-setup --refresh 144       # pin the refresh rate
sudo waydroid-nvidia-setup --restore-official-vendor   # back to stock Waydroid
```

**Run `sudo waydroid-nvidia-setup` again after every NVIDIA driver or package update**, otherwise
Waydroid refuses to start.

### 5. Start the session

```sh
waydroid session start
```

### 6. Verify GPU acceleration

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

The line should mention `ANGLE (NVIDIA` and not a software renderer such as `swiftshader`.

## Driver modes

| Mode | How it works | Pick it when |
|------|--------------|--------------|
| `nvidia-prolapse` (default) | Our open-source driver (Mesa NVK plus our own NVIDIA backend) runs inside Android and talks to the kernel module directly | almost always: it has video decode and the widest driver support |
| `venus` | Android's Vulkan calls go over a socket to the NVIDIA driver on the host | the default mode fails on your machine; slowest, needs the open kernel module |
| `glibc-shim` | Your host's own NVIDIA driver (550 or newer) runs inside Android through our compatibility libraries | you want NVIDIA's own driver and shader compiler |

Apps get OpenGL ES through ANGLE by default. `--native-gl on` uses the mode's own GL driver instead:
our `nvrm` in `nvidia-prolapse`, NVIDIA's GLES in `glibc-shim` (driver 570 or newer).

## ARM translation (running ARM apps on AMD/Intel CPUs)

An x86 Waydroid only runs x86 APKs. ARM apps need a translation layer.

**libndk for AMD CPUs, libhoudini for Intel CPUs.**

```sh
cd ~
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
nix-shell -p lzip --run "sudo venv/bin/python3 main.py install libndk"
```

Restart the container to activate it:

```sh
sudo systemctl restart waydroid-container
```

Verify:

```sh
echo "getprop ro.product.cpu.abilist" | sudo waydroid shell
# should list arm64-v8a, armeabi-v7a
```

## Daily use

| Command | Purpose |
|---------|---------|
| `waydroid status` | Container and session status |
| `waydroid show-full-ui` | Show the Android desktop window |
| `waydroid app install path/to/app.apk` | Install an APK |
| `waydroid app launch <package>` | Launch an app (e.g. `com.android.chrome`) |
| `waydroid shell` | Android shell (or `echo "cmd" \| sudo waydroid shell` for one command) |
| `echo "getprop <key>" \| sudo waydroid shell` | Read an Android property |
| `sudo waydroid shell input tap x y` | Simulate a touch |
| `sudo waydroid shell input keyevent KEYCODE_BACK` | Simulate a key |
| `sudo waydroid-nvidia-setup` | Reconfigure after a driver or package update (required) |

`lib/waydroid-nvidia/wd-native` inside the package is upstream's root helper (the whitelisted entry
point for `dev/driver-mode`, `dev/source-native` and friends); derive its path from
`readlink -f $(command -v waydroid-nvidia-setup)`.

List installed apps:

```sh
echo "pm list packages" | sudo waydroid shell
```

### Restart Waydroid

```sh
# stop the old session
pkill -f "waydroid session"

# restart the container
sudo systemctl restart waydroid-container

# start the session again
waydroid session start
```

## Packages

| `nix build .#<attr>` | Purpose |
|----------------------|---------|
| `virglrenderer-nvidia` | Host Venus render server (virglrenderer with the NVIDIA patches, from source) |
| `waydroid-nvidia` | Waydroid Python tools with upstream's two NVIDIA patches (from source) |
| `guest-nvidia` | Guest Vulkan driver `libvulkan_virtio.so` plus gralloc `libgbm_mesa_wrapper.so` (release asset) |
| `guest-prebuilts-nvidia` | Guest hwcomposer, ANGLE and surfaceflinger (release asset) |
| `native-bundle-nvidia` | Upstream's `native-x86_64` release bundle: the `nvidia-prolapse` Mesa NVK + Rust RM payload, the gate programs and the glibc-shim tree |
| `vendor-image-nvidia` | Upstream's vendor image (a Waydroid OTA zip) and its OTA channel JSON |
| `waydroid-nvidia-full` | All of the above plus `waydroid-nvidia-setup`, systemd units, udev rules and tmpfiles |
| `default` | Same as `waydroid-nvidia-full` |

`waydroid-nvidia-full` is about 360 MB (about 140 MB of native payload, 190 MB of vendor image).

The native payload is staged with upstream's own `packaging/native/install-native.sh`, and
`postFixup` re-verifies every file against `BUILD-RECORD.json` (plus the vendor zip against its
channel), so the payload in the store path is byte-identical to the release. The paths upstream
hardcodes (`/usr/lib/waydroid-nvidia`, `/usr/lib/waydroid`, `/usr/bin/python3`) are rewritten to
store paths at build time, except inside `native/release/` — that is the verified payload.

## Architecture

Default mode (`nvidia-prolapse`): the Vulkan driver inside Android talks to the kernel module
directly; the host only provides the kernel module.

```
┌─────────────────────────────────────────────────┐
│                  Host (NixOS)                    │
│                                                  │
│  ┌─────────────────────┐                         │
│  │  waydroid session   │                         │
│  │  (Python)           │                         │
│  └────────┬────────────┘                         │
│           │ binder                              │
│           ▼                                      │
│  ┌─────────────────────────────┐                 │
│  │  LXC container (Android 13) │                 │
│  │  ┌────────────────────────┐ │                 │
│  │  │ SurfaceFlinger         │ │                 │
│  │  │ hwcomposer             │ │                 │
│  │  │ vulkan.nvidia.so (NVK) │ │                 │
│  │  │ libnv_bionic_native    │ │                 │
│  │  └───────────┬────────────┘ │                 │
│  └──────────────┼──────────────┘                 │
│                 │ /dev/nvidia*, /dev/dri         │
│                 ▼                                │
│         NVIDIA kernel module + GPU               │
└─────────────────────────────────────────────────┘
```

`venus` additionally runs a render server on the host (the `wd-venus` user service) and Android
forwards its Vulkan calls over a socket:

```
┌─────────────────────┐   ┌───────────────────┐
│  waydroid session   │   │  wd-venus         │
│  (Python)           │   │  virgl_test_server│
└────────┬────────────┘   │  ┌──────────────┐ │
         │ binder         │  │virgl_render  │ │
         ▼                │  │_server       │ │
┌─────────────────────┐   │  │  dlopen()    │ │
│  LXC container      │   │  │ libvulkan.so │ │
│  vulkan.virtio.so   │───┼──┘  (venus.sock)│ │
└─────────────────────┘   └──────────────────┘
```

`nvidia-prolapse` and `glibc-shim` do not need `wd-venus`; the module leaves it off for
`mode = "nvidia-prolapse"` and on for `mode = null` / `"venus"`.

### What the packaging layer does

Upstream assumes a mutable `/etc` and a distro python, as on Arch. Both are rewritten at build time;
the runtime logic stays upstream's:

| Upstream | Here |
| --- | --- |
| Hardcoded `/usr/lib/waydroid-nvidia`, `/usr/lib/waydroid`, `/usr/lib/udev` | `substituteInPlace` to store paths at build time |
| `/usr/bin/python3` runs `waydroid.py` (the container unit's `ExecStartPre`, `waydroid upgrade -o`) | rewritten to the interpreter in `waydroid.py`'s shebang (the only one with dbus/gi/gbinder), asserted at build time with `import` |
| The installer writes `/etc/systemd/system/waydroid-container.service.d/` | the package generates the same file at build time with upstream's own `render_override()`, and the module installs it into `/etc` (read-only on NixOS); the scripts' own writes and backups go to `/var/lib/waydroid-nvidia/systemd/` |
| pacman hook / alpm upgrade hook | not used; the module's systemd / udev / tmpfiles integration replaces it |
| The native bundle re-checks its hashes against `BUILD-RECORD.json` at runtime | strip and patchELF are off, and `postFixup` re-checks all 68 + 38 files |
| virglrenderer / Mesa / ANGLE built from source | kept for `virglrenderer` only; everything else comes from the upstream release |

## Known issues

- On some setups the mouse cursor is invisible inside Android (upstream
  [#36](https://github.com/Shiro836/waydroid-nvidia/issues/36))
- Above about 333 Hz the display can stall; cap the rate with `sudo waydroid-nvidia-setup --refresh <hz>`
- Only Android 13 for now

## Development

Build locally:

```sh
nix build .#waydroid-nvidia-full
```

Try the module without deploying:

```nix
# in /etc/nixos/flake.nix
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## Credits

All patches and prebuilt artifacts come from
[Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia). This repository only adds
the Nix packaging layer.

## License

MIT for the packaging layer. Upstream projects keep their own licenses.
