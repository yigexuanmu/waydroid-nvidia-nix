[English](README.en.md) — English version

# waydroid-nvidia-nix

**基于 NVIDIA 的 Waydroid GPU 加速 — 容器内原生运行，无 VM。自包含 fork，上游源码已完整 vendor 进本仓库。**

[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

本仓库是 [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)
的自包含 fork（`Neo` 分支）：上游源码、patches、构建脚本全部 vendor 进仓库，
并额外合入了三个上游 PR：
[#4](https://github.com/Shiro836/waydroid-nvidia/pull/4)（新增 XBGR2101010 / NV12 /
P010 gralloc 格式支持，以及 ETC2 硬件特性探测）、
[#12](https://github.com/Shiro836/waydroid-nvidia/pull/12)（LINEAR 内存截图色带修复）和
[#20](https://github.com/Shiro836/waydroid-nvidia/pull/20)
（hwcomposer 崩溃修复、Scudo 竞态修复、Venus socket 加固、setup 健壮性等）。
以 Nix flake 形式提供 5 个包、overlay 和 NixOS module，所有组件直接从仓库内源码构建。

```
Android app ── Vulkan ──▶ guest Mesa Venus ── unix socket ──▶ host renderer
                                                                   │
KWin ◀── hwcomposer ◀── gralloc imports ◀── NVIDIA dmabufs ◀── NVIDIA driver
```

缓冲区在宿主机侧以 NVIDIA block-linear 图像分配，并以原生 NVIDIA dmabuf 直达合成器。
GL 走 ANGLE，ASTC 纹理由 compute shader 模拟，帧同步完全在 GPU 侧完成。

## 相比上游的修复

除 PR #4 的格式扩展外，本分支还合入了 #12 和 #20，覆盖了一批实际影响使用的缺陷：

| 症状 | 上游 PR | 根因与修法 |
|------|---------|-----------|
| 截屏 / 录屏出现水平色带 | [#12](https://github.com/Shiro836/waydroid-nvidia/pull/12) | CPU 可映射缓冲区原先落在内核 udmabuf 的 LINEAR 内存上，NVIDIA 在其中渲染异常。改为优先使用 vtest 自己分配的 LINEAR 内存（不可渲染的格式回退到 udmabuf），并把线性内存属性由 `HOST_CACHED` 修正为 `HOST_COHERENT` |
| 打开特定应用即崩溃 | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | hwcomposer 现在拒绝导入自己未分配的 `DRM_FORMAT_MOD_LINEAR` dmabuf（issue #11） |
| 随机 Scudo 崩溃 | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | hwcomposer 格式列表的并发读写数据竞争，加 `formats_mutex` |
| SystemUI 崩溃循环 | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | `waydroid-nvidia-setup` 每次清理 per-app `code_cache`（issue #13） |
| 视频画面异常 | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | NV12 改为真正的双平面布局（issue #16），uv 平面尺寸向上取整，奇数高度不再分配不足 |
| Venus socket 对所有本地用户可见 | [#20](https://github.com/Shiro836/waydroid-nvidia/pull/20) | socket 从共享的 root 属主 1777 目录 `/run/waydroid-venus` 移到桌面用户私有的 `$XDG_RUNTIME_DIR/waydroid-venus` |

**socket 位置变更（升级必读）**：Venus socket 现在位于 `$XDG_RUNTIME_DIR/waydroid-venus/venus.sock`，
由 `wd-venus.service` 的 `RuntimeDirectory=waydroid-venus` 在每次登录时自动创建。
旧的 `/run/waydroid-venus/` 不再使用，之前手工创建的同名目录可以删掉。

## 前置要求

- **NVIDIA 开源内核模块**（`nvidia-open`/`nvidia-open-dkms`），对应 **Turing（RTX 20 / GTX 16）或更新** 的显卡
- 驱动 **595.71+**（推荐 610.x），开启 `nvidia-drm.modeset=1`
- Wayland 会话（在 KWin / Plasma 6 上测试）
- 内核 `binder`、`udmabuf` 模块

## 快速开始

### 1. 添加 flake 输入

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

### 2. 启用模块

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
}
```

`services.waydroid-nvidia.package` 默认即为 flake 的 `waydroid-nvidia-full`，无需手动指定。

### 3. 部署

```sh
sudo nixos-rebuild switch --flake .#myhost
```

### 4. 初始化并启动

```sh
sudo waydroid init                     # 下载 Android 镜像
sudo waydroid-nvidia-setup --refresh 144   # --refresh 匹配显示器刷新率
systemctl --user enable --now wd-venus.service
nohup waydroid session start &>/dev/null &
```

`waydroid-nvidia-setup` 必须通过 `sudo` 从**桌面用户自己的会话**运行（不是 root 登录 shell，
也不是 SSH 会话）：它需要一个桌面用户的 `$XDG_RUNTIME_DIR` 来定位 Venus socket。缺这个
环境时会直接报错退出，而不是猜一个路径。

### 5. 验证 GPU 加速

```sh
sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
```

预期输出示例：

```
GLES: Google Inc. (NVIDIA), ANGLE (NVIDIA, Vulkan 1.3.341 (NVIDIA Virtio-GPU Venus (NVIDIA GeForce RTX 4060 Ti) (0x00002788)), venus-26.0.65.35), OpenGL ES 3.2 (ANGLE 2.1.1 git hash: c1a25085dd9e)
```

## ARM 应用运行（x86 上运行 ARM 应用）

Waydroid 在 x86 上默认只能运行 x86 APK。安装 ARM 转译层即可运行 ARM 应用。

**AMD CPU → 用 libndk；Intel CPU → 用 libhoudini。**

```sh
cd ~
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
nix-shell -p lzip --run "sudo venv/bin/python3 main.py install libndk"
```

重启容器：

```sh
sudo systemctl restart waydroid-container
```

验证：

```sh
echo "getprop ro.product.cpu.abilist" | sudo waydroid shell
# 应包含 arm64-v8a, armeabi-v7a
```

## 包一览

| `nix build .#<attr>` | 说明 |
|----------------------|------|
| `virglrenderer-nvidia` | 宿主机 Venus 渲染服务（从源码构建，含 NVIDIA patches、PR#4 格式支持与 #12/#20 的 LINEAR / NV12 修复） |
| `waydroid-nvidia` | 打过补丁的 Waydroid Python 工具（从源码构建） |
| `guest-nvidia` | 客户机 Vulkan 驱动 `libvulkan_virtio.so` + gralloc `libgbm_mesa_wrapper.so`（CI 预编译） |
| `guest-prebuilts-nvidia` | 客户机 hwcomposer + ANGLE + surfaceflinger（CI 预编译） |
| `waydroid-nvidia-full` | 上述全部 + systemd 单元 + udev 规则 + setup 脚本（Venus socket 目录由 `RuntimeDirectory=` 自动创建，不再需要 tmpfiles） |
| `default` | 同 `waydroid-nvidia-full` |

也可通过 `overlays.default` 或直接引用 `packages.x86_64-linux.<attr>` 使用。

## 架构

```
┌─────────────────────────────────────────────────┐
│                  宿主机 (NixOS)                   │
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

## 常见问题

**合成器不在 NVIDIA GPU 上**（显示器接在其他 GPU / 核显驱动笔记本屏）：合成器无法显示本栈的
NVIDIA 缓冲区，Waydroid 窗口会立即崩溃。可用 `gamescope` 将 Waydroid 嵌套固定在 NVIDIA GPU 上运行。

详见仓库内 [`docs/troubleshooting.md`](docs/troubleshooting.md)。

## 开发

```sh
nix build .#waydroid-nvidia-full
```

验证打包结果（不需要部署到系统）：

```sh
P=$(nix eval --impure --raw .#packages.x86_64-linux.waydroid-nvidia-full)
grep -E 'RuntimeDirectory=|socket-path' $P/share/systemd/user/wd-venus.service
```

应当能看到 `RuntimeDirectory=waydroid-venus` 和 `--socket-path %t/waydroid-venus/venus.sock`
—— 两者必须一致，且要与 `waydroid-nvidia-setup` 写进 `waydroid.cfg` 的
`nvidia_venus_socket` 路径指向同一个位置。
模块本地测试（不部署到全系统）：

```nix
inputs.waydroid-nvidia-nix.url = "path:/path/to/waydroid-nvidia-nix";
```

## 许可证

MIT（打包层）。上游项目遵循各自许可证。`patches/` 下的文件是各自上游的衍生作品，遵循对应上游许可证。
