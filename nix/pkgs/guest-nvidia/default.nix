{
  lib
, stdenv
, fetchurl
}:

let
  version = "0.1.0-rc3";

  tarball = fetchurl {
    name = "waydroid-nvidia-guest-android-x86_64-v${version}.tar.zst";
    url = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}/waydroid-nvidia-guest-android-x86_64-v${version}.tar.zst";
    hash = "sha256-nPWORwoSZnv79W0qzikTgTGCOYCU7Byq69L+0BX5Ue8=";
  };
in
stdenv.mkDerivation {
  pname = "guest-nvidia";
  inherit version;

  src = tarball;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib/waydroid-nvidia/guest
    tar --zstd -xf $src -C $out/lib/waydroid-nvidia/guest
  '';

  meta = {
    description = "Guest Android GPU stack for waydroid-nvidia (libvulkan_virtio.so + libgbm_mesa_wrapper.so)";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
