{
  lib
, stdenv
, python3
, python3Packages
, nftables
, dnsmasq
, gtk3
, dbus
, lxc
, wnv-src
}:

let
  pname = "waydroid-nvidia";
  version = "0.2.0";

  # Pinned upstream commit from packaging/ci/pins.env
  waydroid-src = builtins.fetchGit {
    url = "https://github.com/waydroid/waydroid.git";
    rev = "a33a5c0b31d89d6ce687381104b30aff4dd2d330";
  };

  python = python3.withPackages (ps: with ps; [
    pygobject3
    dbus-python
    lxc
    gbinder-python
  ]);
in
stdenv.mkDerivation {
  inherit pname version;

  src = waydroid-src;

  # 0001: venus bind-mounts that survive `waydroid upgrade`, suspend_action=none, drm_device
  # 0002: the nvidia-prolapse/glibc-shim driver modes + tools/helpers/nvidia_native.py
  patches = [
    "${wnv-src}/patches/waydroid/0001-nvidia-integration.patch"
    "${wnv-src}/waydroid/0001-lxc-nvidia-native-mounts.patch"
  ];

  # the patch must install the very file the bundled native tools are built from
  postPatch = ''
    cmp ${wnv-src}/waydroid/nvidia_native.py tools/helpers/nvidia_native.py
  '';

  nativeBuildInputs = [ python ];

  buildInputs = [ nftables dnsmasq gtk3 dbus lxc ];

  dontConfigure = true;

  buildPhase = "true";

  installPhase = ''
    patchShebangs tools/
    make install DESTDIR=$out USE_NFTABLES=1 PREFIX=
    patchShebangs $out/lib/waydroid
  '';

  meta = {
    description = "Patched waydroid with NVIDIA GPU acceleration support";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
