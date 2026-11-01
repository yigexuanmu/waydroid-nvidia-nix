{
  lib
, stdenv
, wnv-src
, virglrenderer-nvidia
, waydroid-nvidia
, guest-nvidia
, guest-prebuilts-nvidia
, native-bundle-nvidia
, vendor-image-nvidia
, lxc
, kmod
, iptables
, nftables
, iproute2
, dnsmasq
, util-linux
, python3
, binutils
, e2fsprogs
, zstd
, coreutils
, gnugrep
, gnused
, gawk
, findutils
}:

let
  version = "0.2.0";
  tag = "v${version}";

  # everything waydroid-nvidia-setup, dev/driver-mode and wd-native shell out to, plus the
  # patched waydroid CLI itself (the setup runs `waydroid init` / `waydroid upgrade -o`).
  # systemctl and udevadm deliberately stay on the host's own systemd.
  setupPath = lib.makeBinPath [
    python3
    binutils # readelf: the guest ABI/SONAME gate
    e2fsprogs # debugfs: reads the bionic runtime out of system.img
    util-linux # unshare: the 32-bit gate cases run in their own PID namespace
    lxc
    kmod
    nftables
    dnsmasq
    iproute2
    iptables
    coreutils
    gnugrep
    gnused
    gawk
    findutils
  ];
in
stdenv.mkDerivation {
  pname = "waydroid-nvidia-full";
  inherit version;

  nativeBuildInputs = [ zstd python3 ];

  # The nvidia-prolapse release bundle is hash-verified against native/release/BUILD-RECORD.json
  # at build time and again at runtime by the gate; stripping, patchELF or shebang-patching its
  # files would void that (they are Android binaries and take no part in the Nix link graph).
  dontStrip = true;
  dontPatchELF = true;

  buildInputs = [ lxc ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # 1. patched waydroid Python tools (same layout as upstream waydroid)
    mkdir -p $out
    cp -r ${waydroid-nvidia}/* $out/
    chmod -R u+w $out

    # 2. host Venus renderer, built from source with upstream's pinned patches (private libdir)
    mkdir -p $out/lib/waydroid-nvidia
    cp -L ${virglrenderer-nvidia}/lib/waydroid-nvidia/* $out/lib/waydroid-nvidia/

    # 3. guest stack (Venus vulkan HAL + gralloc) and 4. guest prebuilts (hwcomposer + ANGLE +
    # surfaceflinger). Both preserve Android's lib/lib64 split.
    mkdir -p $out/lib/waydroid-nvidia/guest
    for guest_dir in ${guest-nvidia}/lib/waydroid-nvidia/guest ${guest-prebuilts-nvidia}/lib/waydroid-nvidia/guest; do
      for f in $(find "$guest_dir" -type f); do
        rel="''${f#$guest_dir/}"
        install -Dm 644 "$f" "$out/lib/waydroid-nvidia/guest/$rel"
      done
    done
    chmod 755 $out/lib/waydroid-nvidia/guest/system/bin/surfaceflinger

    # 5. nvidia-prolapse: the release bundle, the vendor image and the tools that stage, gate
    # and activate them, laid out by upstream's own installer (it verifies the bundle against
    # BUILD-RECORD.json and the image against its OTA channel, and writes native/PACKAGED).
    native_root=$(mktemp -d)
    bash ${wnv-src}/packaging/native/install-native.sh \
      ${wnv-src} \
      ${native-bundle-nvidia} \
      ${vendor-image-nvidia}/waydroid-nvidia-vendor-x86_64-v${version}.zip \
      ${vendor-image-nvidia}/waydroid-nvidia-vendor-ota-v${version}.json \
      "$native_root" ${tag}
    cp -a "$native_root/usr/lib/waydroid-nvidia/." $out/lib/waydroid-nvidia/
    rm -rf "$native_root"

    # Upstream keeps two copies of the helper and compares them by sha256 at runtime (the packaged
    # install must carry exactly its own generator). The waydroid tools' shebangs are already
    # rewritten by the waydroid build, so make the bundle's copy literally the same file.
    cp $out/lib/waydroid/tools/helpers/nvidia_native.py \
      $out/lib/waydroid-nvidia/native/waydroid/nvidia_native.py

    # 6. host integration files from upstream
    mkdir -p $out/bin
    mkdir -p $out/lib/systemd/user
    mkdir -p $out/lib/tmpfiles.d
    mkdir -p $out/lib/udev/rules.d

    # Patch waydroid-container.service to use the Nix store path
    substituteInPlace $out/lib/systemd/system/waydroid-container.service \
      --replace-fail '/usr/bin/waydroid' "$out/bin/waydroid"

    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/wd-venus.service \
      $out/lib/systemd/user/wd-venus.service
    substituteInPlace $out/lib/systemd/user/wd-venus.service \
      --replace-fail '/usr/lib/waydroid-nvidia' "$out/lib/waydroid-nvidia"
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-venus.tmpfiles \
      $out/lib/tmpfiles.d/waydroid-venus.conf
    # udmabuf uaccess for the seated user (Venus CPU-mappable gralloc buffers)
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia.rules \
      $out/lib/udev/rules.d/70-waydroid-nvidia.rules
    # the NVIDIA render node as a systemd device unit the container unit waits for at boot
    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-gpu.rules \
      $out/lib/udev/rules.d/70-waydroid-nvidia-gpu.rules

    cp ${wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-setup \
      $out/bin/waydroid-nvidia-setup
    chmod +x $out/bin/waydroid-nvidia-setup

    # 7. upstream hardcodes its distro prefix (/usr/lib/waydroid-nvidia, the system waydroid tree,
    # /usr/bin/python3 for the container unit's ExecStartPre). Point all of it at the store.
    # native/release/ is skipped: its files are sha256-checked at runtime by the gate.
    mapfile -t to_patch < <(grep -rIl --exclude-dir=release \
      -e '/usr/lib/waydroid' -e '/usr/bin/python3' $out || true)
    subst() {  # pattern, replacement: only in the files that carry it
      local f
      for f in "''${to_patch[@]}"; do
        if grep -qF -- "$1" "$f"; then
          substituteInPlace "$f" --replace-fail "$1" "$2"
        fi
      done
    }
    # upstream's /usr/bin/python3 is the distro python, which carries Waydroid's own runtime.
    # `${python3}` would not: tools/source-native's waydroid_argv() runs
    # `[PYTHON, $out/lib/waydroid/waydroid.py]` (that is how `waydroid upgrade -o` and
    # `driver-mode verify-active` are invoked), and waydroid.py imports dbus/gi/gbinder, which only
    # the waydroid package's python env provides. That env is exactly waydroid.py's shebang, so read
    # it back instead of hardcoding it, and fail the build if it is not a working Waydroid runtime.
    wd_python=$(sed -n '1s/^#!//p' $out/lib/waydroid/waydroid.py)
    "$wd_python" -I -c 'import dbus.mainloop.glib, gi, gbinder' \
      || { echo "waydroid.py's interpreter ($wd_python) cannot import dbus/gi/gbinder" >&2; exit 1; }

    # longest first: -nvidia paths must not be rewritten by the plain waydroid rule
    subst '/usr/lib/waydroid-nvidia' "$out/lib/waydroid-nvidia"
    subst '/usr/lib/udev/rules.d' "$out/lib/udev/rules.d"
    subst '/usr/lib/waydroid' "$out/lib/waydroid"
    subst '/usr/bin/python3' "$wd_python"

    # 8. the setup must find the tools it shells out to, and the waydroid CLI of this package,
    # without relying on the caller's PATH after sudo. Inserted right after the real
    # `set -euo pipefail`, which is where `--help` stops printing, so upstream's help is intact.
    path_line="export PATH=\"$out/bin:${setupPath}:\$PATH\""
    substituteInPlace $out/bin/waydroid-nvidia-setup \
      --replace-fail 'set -euo pipefail
# Tool output parsed here' "set -euo pipefail
$path_line
# Tool output parsed here"

    # 9. verify critical files
    for f in \
      $out/lib/waydroid-nvidia/virgl_test_server \
      $out/lib/waydroid-nvidia/virgl_render_server \
      $out/lib/waydroid-nvidia/libvirglrenderer.so.1 \
      $out/lib/waydroid-nvidia/guest/vendor/lib/hw/vulkan.virtio.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/hw/vulkan.virtio.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/libgbm_mesa_wrapper.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib/egl/libEGL_angle.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/egl/libEGL_angle.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/egl/libGLESv2_angle.so \
      $out/lib/waydroid-nvidia/guest/vendor/lib64/hw/hwcomposer.waydroid.so \
      $out/lib/waydroid-nvidia/guest/system/bin/surfaceflinger \
      $out/lib/waydroid-nvidia/wd-native \
      $out/lib/waydroid-nvidia/native/PACKAGED \
      $out/lib/waydroid-nvidia/native/release/BUILD-RECORD.json \
      $out/lib/waydroid-nvidia/native/dev/driver-mode \
      $out/lib/waydroid-nvidia/native/packaging/native/vendor_image.py \
      $out/bin/waydroid-nvidia-setup \
      $out/bin/waydroid \
      $out/lib/systemd/user/wd-venus.service \
      $out/lib/tmpfiles.d/waydroid-venus.conf \
      $out/lib/udev/rules.d/70-waydroid-nvidia.rules \
      $out/lib/udev/rules.d/70-waydroid-nvidia-gpu.rules
    do
      [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
    done
    for d in \
      $out/lib/waydroid-nvidia/vendor \
      $out/lib/waydroid-nvidia/native/release/payload/odm/bin/hw
    do
      [ -d "$d" ] || { echo "missing: $d" >&2; exit 1; }
    done
    for f in $out/lib/waydroid-nvidia/vendor/*.zip; do
      [ -f "$f" ] || { echo "missing vendor zip in $out/lib/waydroid-nvidia/vendor" >&2; exit 1; }
    done

    # no hardcoded distro prefix may survive outside the hash-checked bundle
    if grep -rIl --exclude-dir=release -e '/usr/lib/waydroid' -e '/usr/bin/python3' $out; then
      echo "files above still hardcode /usr/lib/waydroid* or /usr/bin/python3" >&2; exit 1;
    fi

    # the packaged install must carry exactly its own generator (dev/source-native compares the two
    # by sha256 at runtime)
    cmp $out/lib/waydroid/tools/helpers/nvidia_native.py \
      $out/lib/waydroid-nvidia/native/waydroid/nvidia_native.py

    runHook postInstall
  '';

  # Everything the bundle contains must be byte-identical to the release: fixupPhase strips and
  # rewrites ELFs in $out by default, so this runs as postFixup (the last step) rather than in
  # installPhase, and fails the build if the store's copy deviates from BUILD-RECORD.json.
  postFixup = ''
    python3 -I ${./verify-bundle.py} $out/lib/waydroid-nvidia ${tag}
  '';

  meta = {
    description = "Complete waydroid-nvidia stack: patched waydroid + host/guest GPU drivers + the nvidia-prolapse vendor image";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
