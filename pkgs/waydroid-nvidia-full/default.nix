{
  lib
, stdenv
, virglrenderer-nvidia
, waydroid-nvidia
, guest-nvidia
, guest-prebuilts-nvidia
, lxc
, kmod
, iptables
, nftables
, iproute2
, dnsmasq
, util-linux
, makeWrapper
}:

let
  version = "0.1.2";
in
stdenv.mkDerivation {
  pname = "waydroid-nvidia-full";
  inherit version;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ lxc ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  postFixup = ''
    wrapProgram $out/bin/waydroid --prefix PATH : ${lib.makeBinPath [ lxc kmod util-linux ]}
    wrapProgram $out/lib/waydroid/data/scripts/waydroid-net.sh \
      --prefix PATH : ${lib.makeBinPath [ lxc kmod iptables nftables iproute2 dnsmasq ]}
  '';

  installPhase = ''
    # 1. patched waydroid Python tools
    mkdir -p $out
    cp -r ${waydroid-nvidia}/* $out/
    chmod -R u+rwx $out

    # 2. host Venus renderer (private libdir)
    mkdir -p $out/lib/waydroid-nvidia
    cp -L ${virglrenderer-nvidia}/lib/waydroid-nvidia/* $out/lib/waydroid-nvidia/

    # 3. guest stack (vulkan driver + gralloc) + 4. guest prebuilts (hwcomposer + ANGLE + surfaceflinger)
    mkdir -p $out/lib/waydroid-nvidia/guest
    for guest_dir in ${guest-nvidia}/lib/waydroid-nvidia/guest ${guest-prebuilts-nvidia}/lib/waydroid-nvidia/guest; do
      for f in $(find "$guest_dir" -type f); do
        rel="''${f#$guest_dir/}"
        install -Dm 644 "$f" "$out/lib/waydroid-nvidia/guest/$rel"
      done
    done
    chmod 755 $out/lib/waydroid-nvidia/guest/system/bin/surfaceflinger

    # 5. host integration files from upstream
    mkdir -p $out/bin
    mkdir -p $out/lib/systemd/user
    mkdir -p $out/lib/udev/rules.d

    # Patch waydroid-container.service to use Nix store path
    substituteInPlace $out/lib/systemd/system/waydroid-container.service \
      --replace-fail '/usr/bin/waydroid' "$out/bin/waydroid"

    cp ${./../../packaging/aur/waydroid-nvidia-bin/wd-venus.service} \
      $out/lib/systemd/user/wd-venus.service
    substituteInPlace $out/lib/systemd/user/wd-venus.service \
      --replace-fail '/usr/lib/waydroid-nvidia' "$out/lib/waydroid-nvidia"
    # The Venus socket directory is NOT a tmpfiles.d entry: wd-venus.service
    # declares RuntimeDirectory=waydroid-venus, so systemd creates it under
    # $XDG_RUNTIME_DIR at mode 0755 inside the desktop user's 0700 runtime dir.
    # (Upstream PR #20 removed the shared, root-owned, world-writable
    # /run/waydroid-venus tmpfiles unit that let any local user reach the
    # socket. The NixOS module's service definition must carry
    # RuntimeDirectory=waydroid-venus too -- see modules/nixos/waydroid-nvidia.nix.)
    cp ${./../../packaging/aur/waydroid-nvidia-bin/waydroid-nvidia.rules} \
      $out/lib/udev/rules.d/70-waydroid-nvidia.rules
    cp ${./../../packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-setup} \
      $out/bin/waydroid-nvidia-setup
    chmod +x $out/bin/waydroid-nvidia-setup
    # Patch hardcoded /usr/lib paths to the Nix store location
    substituteInPlace $out/bin/waydroid-nvidia-setup \
      --replace-fail '/usr/lib/waydroid-nvidia' "$out/lib/waydroid-nvidia"

    # 6. verify critical files
    for f in \
      $out/lib/waydroid-nvidia/virgl_test_server \
      $out/lib/waydroid-nvidia/virgl_render_server \
      $out/lib/waydroid-nvidia/libvirglrenderer.so.1 \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/hw/vulkan.virtio.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/libgbm_mesa_wrapper.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/hw/hwcomposer.waydroid.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/egl/libEGL_angle.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/egl/libGLESv2_angle.so \
      $out/lib/waydroid-nvidia/guest/system/bin/surfaceflinger \
      $out/bin/waydroid-nvidia-setup \
      $out/bin/waydroid \
      $out/lib/systemd/user/wd-venus.service \
      $out/lib/udev/rules.d/70-waydroid-nvidia.rules
    do
      [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
    done
  '';

  meta = {
    description = "Complete waydroid-nvidia stack: patched waydroid + host/guest GPU drivers";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
