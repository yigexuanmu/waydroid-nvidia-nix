{
  lib
, stdenv
, wnv-src
, virglrenderer-nvidia
, waydroid-nvidia
, guest-nvidia
, guest-prebuilts-nvidia
, lxc
, kmod
, makeWrapper
}:

let
  version = "0.1.0-rc3";
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
    wrapProgram $out/bin/waydroid --prefix PATH : ${lib.makeBinPath [ lxc kmod ]}
  '';

  installPhase = ''
    # 1. patched waydroid Python tools
    mkdir -p $out
    cp -r ${waydroid-nvidia}/* $out/
    chmod -R u+rwx $out

    # 2. host Venus renderer (private libdir)
    mkdir -p $out/lib/waydroid-nvidia
    cp -L ${virglrenderer-nvidia}/lib/waydroid-nvidia/* $out/lib/waydroid-nvidia/

    # 3. guest stack (vulkan driver + gralloc)
    mkdir -p $out/lib/waydroid-nvidia/guest
    cp -L ${guest-nvidia}/lib/waydroid-nvidia/guest/* $out/lib/waydroid-nvidia/guest/

    # 4. guest prebuilts (hwcomposer + ANGLE + surfaceflinger)
    cp -L ${guest-prebuilts-nvidia}/lib/waydroid-nvidia/guest/* $out/lib/waydroid-nvidia/guest/

    # 5. host integration files from upstream
    mkdir -p $out/bin
    mkdir -p $out/lib/systemd/user
    mkdir -p $out/lib/tmpfiles.d
    mkdir -p $out/lib/udev/rules.d

    # Patch waydroid-container.service to use Nix store path
    substituteInPlace $out/lib/systemd/system/waydroid-container.service \
      --replace-fail '/usr/bin/waydroid' "$out/bin/waydroid"

    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/wd-venus.service \
      $out/lib/systemd/user/wd-venus.service
    substituteInPlace $out/lib/systemd/user/wd-venus.service \
      --replace-fail '/usr/lib/waydroid-nvidia' "$out/lib/waydroid-nvidia"
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-venus.tmpfiles \
      $out/lib/tmpfiles.d/waydroid-venus.conf
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia.rules \
      $out/lib/udev/rules.d/70-waydroid-nvidia.rules
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-setup \
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
      $out/lib/waydroid-nvidia/guest/libvulkan_virtio.so \
      $out/lib/waydroid-nvidia/guest/libgbm_mesa_wrapper.so \
      $out/lib/waydroid-nvidia/guest/hwcomposer.waydroid.so \
      $out/bin/waydroid-nvidia-setup \
      $out/bin/waydroid \
      $out/lib/systemd/user/wd-venus.service \
      $out/lib/tmpfiles.d/waydroid-venus.conf \
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
