[English](README.en.md) — Read this document in English

# waydroid-nvidia-nix

**GPU 硬件加速的 Waydroid + NVIDIA 显卡**，打包为 Nix 包和 NixOS 模块。

打包层对齐上游 [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia) 的
[**v0.2.0**](https://github.com/Shiro836/waydroid-nvidia/releases/tag/v0.2.0) 发布版：补丁、发布产物、
安装脚本、udev/systemd 集成、目录布局全部取自该 tag，本仓库不 vendoring 任何代码。

- Host 端（virglrenderer）和 Waydroid Python 工具从源码构建
- 上游 v0.2.0 的三个发布产物（native bundle、vendor 镜像、guest 组件）直接取发布包并做 sha256 校验

## 前置要求

- **NVIDIA 内核模块**，开启 `nvidia-drm.modeset=1`
  - 默认模式 `nvidia-prolapse`：开源 `nvidia-open` 或闭源内核模块都可以，**不需要** host 用户态驱动
  - `venus` 模式：需要开源内核模块
  - `glibc-shim` 模式：使用 host 自己的 NVIDIA 用户态驱动（≥ 550，另需 32 位库）
- Wayland 会话，运行在 NVIDIA 显卡上
- `binder` Linux 内核模块（模块已自动 `boot.kernelModules = [ "binder_linux" ]`）
- `udmabuf` 内核模块（仅 `venus` 模式需要）

## 快速开始

### 1. 添加 flake 输入

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

### 2. 启用模块

建议将 waydroid-nvidia 配置放在单独文件，如 `configuration/modules/services/waydroid-nvidia.nix`：

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

  # 可选项，见下表
  # services.waydroid-nvidia.mode = "nvidia-prolapse";
  # services.waydroid-nvidia.nativeGl = "off";
  # services.waydroid-nvidia.refreshRate = 144;
}
```

或直接内联在 `flake.nix` 的 modules 里：

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

如果用了单独文件，在主 modules 列表中引入：

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

模块选项：

| 选项 | 默认 | 说明 |
|------|------|------|
| `enable` | `false` | 启用集成（systemd unit、udev 规则、tmpfiles）|
| `package` | flake 内 `waydroid-nvidia-full` | 使用的包 |
| `mode` | `null` | 传给 `waydroid-nvidia-setup --mode`：`nvidia-prolapse` / `glibc-shim` / `venus`。`null` 表示沿用 `waydroid.cfg` 里的值，全新安装则是上游默认 `nvidia-prolapse` |
| `nativeGl` | `null` | 传给 `--native-gl on\|off`：用该模式自带的 GL 驱动代替 ANGLE。`null` 表示沿用现状（全新安装为 off）|
| `refreshRate` | `null` | 传给 `--refresh <hz>`：覆盖 hwcomposer 上报的刷新率。`null` 表示使用显示器当前最快的模式 |

> 这些选项只决定提示命令里带哪些参数，以及是否启动 `wd-venus` 用户服务；真正写入
> `waydroid.cfg` 的是 `sudo waydroid-nvidia-setup`（它还要打镜像、跑 GPU 门禁测试）。

选择方案：

| 方式 | 说明 |
|------|------|
| `waydroid-nvidia-nix.nixosModules.waydroid-nvidia` | 直接引用模块，`package` 默认使用 flake 内包 |
| `waydroid-nvidia-nix.overlays.default` | 叠加到 `nixpkgs.overlays`，然后从 `pkgs.waydroid-nvidia-full` 引用 |
| `waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full` | 单独包，手动指定服务 `package` |

推荐第一种。

### 3. 部署

```sh
sudo nixos-rebuild switch --flake .#myhost
```

### 4. 配置 NVIDIA 加速栈

```sh
sudo waydroid-nvidia-setup
```

setup 会检查系统、在你的 GPU 上跑驱动门禁测试，然后才安装上游的 Android vendor 镜像（你原有的
vendor 镜像会备份）。全新安装时它会自动执行 `waydroid init`；需要 Google 服务用
`sudo waydroid-nvidia-setup -s GAPPS`。

常用参数：

```sh
sudo waydroid-nvidia-setup --mode venus        # 切换驱动模式
sudo waydroid-nvidia-setup --native-gl on      # 用该模式自带的 GL 驱动（nvidia-prolapse / glibc-shim）
sudo waydroid-nvidia-setup --refresh 144       # 固定刷新率
sudo waydroid-nvidia-setup --restore-official-vendor   # 回到原版 Waydroid
```

**每次升级 NVIDIA 驱动或本包后都要重跑 `sudo waydroid-nvidia-setup`**，否则 Waydroid 拒绝启动。

### 5. 启动会话

```sh
waydroid session start
```

### 6. 验证 GPU 加速

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

输出应包含 `ANGLE (NVIDIA` 之类的字样，而不是 `swiftshader` 之类的软件渲染。

## 驱动模式

| 模式 | 原理 | 适用 |
|------|------|------|
| `nvidia-prolapse`（默认）| 开源驱动（Mesa NVK + 我们自己的 NVIDIA 后端）在 Android 内运行，直接和内核模块通信 | 大多数情况：支持视频解码，驱动覆盖面最广 |
| `venus` | Android 的 Vulkan 调用经 socket 转发到 host 上的 NVIDIA 驱动 | 默认模式在你的机器上失败时；最慢，需要开源内核模块 |
| `glibc-shim` | host 自己的 NVIDIA 驱动（≥ 550）通过兼容库在 Android 内运行 | 想用 NVIDIA 官方驱动与着色器编译器时 |

默认应用通过 ANGLE 获得 OpenGL ES；`--native-gl on` 改用该模式自带的 GL 驱动（`nvidia-prolapse`
用我们的 `nvrm`，`glibc-shim` 用 NVIDIA 的 GLES，需要驱动 ≥ 570）。

## ARM 翻译层（AMD/Intel CPU 运行 ARM 应用）

x86 架构的 Waydroid 默认只运行 x86 的 APK。要运行 ARM 应用需要安装翻译层。

**AMD CPU 推荐 libndk，Intel CPU 推荐 libhoudini。**

```sh
cd ~
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
nix-shell -p lzip --run "sudo venv/bin/python3 main.py install libndk"
```

重启容器使翻译层生效：

```sh
sudo systemctl restart waydroid-container
```

验证：

```sh
echo "getprop ro.product.cpu.abilist" | sudo waydroid shell
# 应包含 arm64-v8a, armeabi-v7a
```

## 日常使用

| 命令 | 说明 |
|------|------|
| `waydroid status` | 查看容器和会话状态 |
| `waydroid show-full-ui` | 显示 Android 桌面窗口 |
| `waydroid app install path/to/app.apk` | 安装 APK |
| `waydroid app launch <package>` | 启动应用（如 `com.android.chrome`）|
| `waydroid shell` | 进入 Android shell（配合 `echo "cmd" \| sudo waydroid shell` 单条执行）|
| `echo "getprop <key>" \| sudo waydroid shell` | 读取 Android 属性 |
| `sudo waydroid shell input tap x y` | 模拟触控 |
| `sudo waydroid shell input keyevent KEYCODE_BACK` | 模拟按键 |
| `sudo waydroid-nvidia-setup` | 驱动或本包更新后重新配置（必做）|

包内 `lib/waydroid-nvidia/wd-native` 是上游的 root helper（`dev/driver-mode`、`dev/source-native`
等脚本的白名单入口），路径可由 `readlink -f $(command -v waydroid-nvidia-setup)` 推出。

查看已安装应用：

```sh
echo "pm list packages" | sudo waydroid shell
```

### 重启 Waydroid

```sh
# 停止旧会话
pkill -f "waydroid session"

# 重启容器
sudo systemctl restart waydroid-container

# 重新启动会话
waydroid session start
```

## 包说明

| `nix build .#<attr>` | 作用 |
|----------------------|------|
| `virglrenderer-nvidia` | Host 端 Venus 渲染服务器（virglrenderer + NVIDIA 补丁，从源码构建）|
| `waydroid-nvidia` | 打过上游两个 NVIDIA 补丁的 Waydroid Python 工具（从源码构建）|
| `guest-nvidia` | Guest 端 Vulkan 驱动 `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so`（发布包）|
| `guest-prebuilts-nvidia` | Guest 端 hwcomposer + ANGLE + surfaceflinger（发布包）|
| `native-bundle-nvidia` | 上游 `native-x86_64` 发布包：`nvidia-prolapse` 的 Mesa NVK + Rust RM 载荷、门禁程序、glibc-shim |
| `vendor-image-nvidia` | 上游 vendor 镜像（Waydroid OTA zip）及其 OTA channel JSON |
| `waydroid-nvidia-full` | 以上全部 + `waydroid-nvidia-setup` + systemd units + udev 规则 + tmpfiles |
| `default` | 同 `waydroid-nvidia-full` |

`waydroid-nvidia-full` 约 360 MB（其中 native 载荷约 140 MB、vendor 镜像约 190 MB）。

构建时会用上游 `packaging/native/install-native.sh` 装好 native 载荷，并在 `postFixup` 里按
`BUILD-RECORD.json` 重新校验每个文件的 sha256（以及 vendor zip 与 channel 的一致性）——所以本包
的 store 路径里的载荷与上游发布包逐字节相同。上游写死的 `/usr/lib/waydroid-nvidia`、
`/usr/lib/waydroid`、`/usr/bin/python3` 在构建时被改写到 store 路径（`native/release/` 例外，
那是被校验的载荷）。

## 架构

默认模式（`nvidia-prolapse`）：Android 内的 Vulkan 驱动直接和内核模块通信，host 只提供内核模块。

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
│         NVIDIA 内核模块 + GPU                    │
└─────────────────────────────────────────────────┘
```

`venus` 模式另外在本机跑一个渲染服务器（`wd-venus` 用户服务），Android 通过 socket 把 Vulkan
调用转发给它：

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

`nvidia-prolapse` 与 `glibc-shim` 模式不需要 `wd-venus`；模块在 `mode = "nvidia-prolapse"` 时
不启用它，`mode = null` / `"venus"` 时启用。

### 打包层做了什么

上游假设 Arch 那样的可变 `/etc` 和系统自带的 python。这些在构建期改写，运行逻辑保持上游原样：

| 上游做法 | 这里 |
| --- | --- |
| 硬编码 `/usr/lib/waydroid-nvidia`、`/usr/lib/waydroid`、`/usr/lib/udev` | 构建期 `substituteInPlace` 指向 store 路径 |
| 用 `/usr/bin/python3` 跑 `waydroid.py`（容器 unit 的 `ExecStartPre`、`waydroid upgrade -o`） | 改写成 `waydroid.py` shebang 里的那个 python 环境（唯一带 dbus/gi/gbinder 的），并在构建期 `import` 断言；`dev/` 下可执行脚本的 `#!/usr/bin/env python3` 也一起指向它（NixOS 没有 `/usr/bin/env`） |
| 安装时写 `/etc/systemd/system/waydroid-container.service.d/` | NixOS 里这个路径是指向 `system-units` 的符号链接，写不了；`Wants=` / `After=` / `ExecStartPre=` 三项在模块里直接写在 unit 上，并用构建期断言盯住上游的 `render_override()`（它一多出东西就红），脚本自己的写入与备份落在 `/var/lib/waydroid-nvidia/systemd/` |
| pacman hook / alpm 升级钩子 | 不用；改用模块的 systemd / udev / tmpfiles 集成 |
| 假设系统已装 `lxc`、防火墙放行 `waydroid0`、`/var/lib/misc` 存在 | 模块补齐（`virtualisation.lxc.enable`、`firewall.trustedInterfaces`、tmpfiles），与 nixpkgs 的 waydroid 模块一致；容器 unit 另有自己的 PATH |
| native bundle 运行时按 `BUILD-RECORD.json` 校验哈希 | 关掉 strip 与 patchELF，`postFixup` 里重新校验 68 + 38 个文件 |
| 从源码构建 virglrenderer / Mesa / ANGLE | 只保留 `virglrenderer`；其余取上游发布产物 |

## 已知问题

- 部分配置下 Android 内看不到鼠标指针（上游 [#36](https://github.com/Shiro836/waydroid-nvidia/issues/36)）
- 刷新率超过约 333 Hz 可能卡顿，用 `sudo waydroid-nvidia-setup --refresh <hz>` 限速
- 目前只支持 Android 13

## 开发

在本地构建：

```sh
nix build .#waydroid-nvidia-full
```

测试本模块（不部署到系统）：

```nix
# 在 /etc/nixos/flake.nix 中
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## 致谢

所有补丁和预编译产物来自 [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)。本仓库只提供 Nix 打包层。

## 许可证

MIT（打包层）。上游项目引用各自许可证。
