{
  lib
, stdenv
, fetchurl
, zstd
}:

let
  version = "0.1.1";

  tarball = fetchurl {
    name = "waydroid-nvidia-guest-android-x86_64-v${version}.tar.zst";
    url = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}/waydroid-nvidia-guest-android-x86_64-v${version}.tar.zst";
    hash = "sha256-fT/JtX8krSPGPu10tFGcGoSdfnzIxR9jeBBliJOg/I0=";
  };
in
stdenv.mkDerivation {
  pname = "guest-nvidia";
  inherit version;

  src = tarball;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zstd ];

  installPhase = ''
    mkdir -p $out/lib/waydroid-nvidia/guest
    tar --zstd -xf "$src" -C $out/lib/waydroid-nvidia/guest
  '';

  meta = {
    description = "Guest Android GPU stack for waydroid-nvidia (libvulkan_virtio.so + libgbm_mesa_wrapper.so)";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
