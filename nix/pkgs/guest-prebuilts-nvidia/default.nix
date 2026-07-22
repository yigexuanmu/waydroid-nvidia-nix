{
  lib
, stdenv
, fetchurl
}:

let
  version = "0.1.0-rc3";

  tarball = fetchurl {
    name = "waydroid-nvidia-guest-prebuilts-v${version}.tar.zst";
    url = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}/waydroid-nvidia-guest-prebuilts-v${version}.tar.zst";
    hash = "sha256-2D3C/cK2iSu8ZTe4ijjQ6YuCS9Kfpyrof7wS8tUxiK4=";
  };
in
stdenv.mkDerivation {
  pname = "guest-prebuilts-nvidia";
  inherit version;

  src = tarball;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib/waydroid-nvidia/guest
    tar --zstd -xf $src -C $out/lib/waydroid-nvidia/guest
  '';

  meta = {
    description = "Prebuilt guest components for waydroid-nvidia (hwcomposer, ANGLE, surfaceflinger)";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
