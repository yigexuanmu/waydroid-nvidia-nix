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
  version = "0.1.1";

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

  patches = [ "${wnv-src}/patches/waydroid/0001-nvidia-integration.patch" ];

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
