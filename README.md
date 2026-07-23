[English](README.en.md) — Read this document in English

# waydroid-nvidia-nix

**GPU 硬件加速的 Waydroid + NVIDIA 显卡**，打包为 Nix 包和 NixOS 模块。

所有组件均引用上游构建，本仓库不 vendoring 任何代码。

- Host 端（virglrenderer）和 Waydroid Python 工具从源码构建
- Guest 端 Android 组件（Vulkan 驱动、hwcomposer、ANGLE、surfaceflinger）从 CI 发布包下载

## 前置要求

- **NVIDIA 开源内核模块** `nvidia-open`，开启 `nvidia-drm.modeset=1`
- NVIDIA 用户态驱动 `nvidia-utils`，建议版本 ≥ 610.x
- Wayland 会话
- `binder` Linux 内核模块（Waydroid 需要）
- `udmabuf` 内核模块（virgl Venus 需要）

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
  services.waydroid-nvidia.refreshRate = 144; # 你的显示器刷新率
  services.waydroid-nvidia.package = inputs.waydroid-nvidia-nix.packages.x86_64-linux.waydroid-nvidia-full;
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

### 4. 初始化 Android 镜像

```sh
sudo waydroid init
```

### 5. 配置 NVIDIA 加速栈

```sh
sudo waydroid-nvidia-setup --refresh 144
# --refresh 参数指定你的显示器刷新率
```

### 6. 启动服务

```sh
nohup waydroid session start &>/dev/null &
```

### 7. 验证 GPU 加速

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

正常输出示例：

```
GLES: Google Inc. (NVIDIA), ANGLE (NVIDIA, Vulkan 1.3.341 (NVIDIA Virtio-GPU Venus (NVIDIA GeForce RTX 4060 Ti) (0x00002788)), venus-26.0.65.35), OpenGL ES 3.2 (ANGLE 2.1.1 git hash: c1a25085dd9e)
```

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
nohup waydroid session start &>/dev/null &
```

## 包说明

| `nix build .#<attr>` | 作用 |
|----------------------|------|
| `virglrenderer-nvidia` | Host 端 Venus 渲染服务器（virglrenderer + NVIDIA 补丁，从源码构建）|
| `waydroid-nvidia` | 打过 NVIDIA 补丁的 Waydroid Python 工具（从源码构建）|
| `guest-nvidia` | Guest 端 Vulkan 驱动 `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so`（CI 预编译）|
| `guest-prebuilts-nvidia` | Guest 端 hwcomposer + ANGLE + surfaceflinger（CI 预编译）|
| `waydroid-nvidia-full` | 以上全部 + systemd units + udev 规则 + tmpfiles + 集成脚本 |
| `default` | 同 `waydroid-nvidia-full` |

## 架构

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
