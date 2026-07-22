# waydroid-nvidia-nix

**Waydroid 在 NVIDIA 显卡上的 GPU 硬件加速——Nix 打包。**

所有来源均引用上游，本仓库不 vendoring 任何代码。

- 包：`github:Shiro836/waydroid-nvidia` 的补丁和预编译产物
- NixOS 模块：systemd 服务、udev 规则、tmpfiles

## 前置要求

- **NVIDIA 开源内核模块**（`nvidia-open`）且开启 `nvidia-drm.modeset=1`
- NVIDIA 用户态驱动（`nvidia-utils`），建议驱动版本 ≥ 610.x
- Wayland 会话（已在 KWin/Plasma 6、Niri 上测试）
- `binder` Linux 内核模块（Waydroid 需要）

## 安装

在 `flake.nix` 中添加：

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
        { nixpkgs.overlays = [ waydroid-nvidia-nix.overlays.default ]; }
        waydroid-nvidia-nix.nixosModules.waydroid-nvidia
        {
          services.waydroid-nvidia.enable = true;
          services.waydroid-nvidia.refreshRate = 144;
        }
      ];
    };
  };
}
```

然后重建系统：

```sh
sudo nixos-rebuild switch --flake .#myhost
```

安装的组件：

| 组件 | 来源 |
|------|------|
| `waydroid`（打过补丁的 Python 工具） | 从 `github:waydroid/waydroid` 构建 + NVIDIA 补丁 |
| `virgl_test_server` + `virgl_render_server` | 从 `gitlab.freedesktop.org/virgl/virglrenderer` 构建 + 4 个补丁 |
| Guest Vulkan 驱动（`libvulkan_virtio.so`） | 来自 `Shiro836/waydroid-nvidia` 的 CI 构建产物 |
| Guest gralloc（`libgbm_mesa_wrapper.so`） | CI 构建产物 |
| Guest 显示 HAL + ANGLE + surfaceflinger | CI 构建的预编译产物 |

## 安装后的步骤

1. **下载 Android 镜像**（和普通 Waydroid 一样）：

   ```sh
   sudo waydroid init
   ```

2. **配置 NVIDIA 加速栈**（将 guest 文件复制到 `/var/lib/waydroid`，写入属性）：

   ```sh
   sudo waydroid-nvidia-setup --refresh 144
   ```

3. **重新登录**（让 `/dev/udmabuf` 的 `uaccess` udev 规则生效）。

4. **启动服务**：

   ```sh
   sudo systemctl enable --now waydroid-container.service
   systemctl --user enable --now wd-venus.service
   waydroid session start
   ```

5. **验证 GPU 加速**：

   ```sh
   sudo waydroid shell dumpsys SurfaceFlinger | grep GLES
   # 应该看到：GLES: ... ANGLE (NVIDIA, Vulkan ... Venus (NVIDIA GeForce ...))
   ```

## 包列表

| `nix build .#<attr>` | 说明 |
|----------------------|------|
| `virglrenderer-nvidia` | Host Venus 渲染服务器（从源码构建） |
| `waydroid-nvidia` | 打过补丁的 Waydroid Python 工具（从源码构建） |
| `guest-nvidia` | Guest Vulkan 驱动 + gralloc 后端（预编译） |
| `guest-prebuilts-nvidia` | Guest hwcomposer + ANGLE + surfaceflinger（预编译） |
| `waydroid-nvidia-full` | 以上所有组件的集合 + 集成文件 |
| `default` | 同 `waydroid-nvidia-full` |

## 致谢

所有补丁和预编译产物来自 [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)。本仓库只提供 Nix 打包层。

## 许可证

MIT（打包层）。上游项目使用 MIT 许可证；补丁使用 MIT；预编译产物包含各自许可下的组件（MIT、GPL、Apache 等）。
