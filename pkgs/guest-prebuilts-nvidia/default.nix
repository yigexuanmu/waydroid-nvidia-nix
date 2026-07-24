{
  lib
, stdenv
, fetchurl
, zstd
}:

let
  version = "0.1.2";

  tarball = fetchurl {
    name = "waydroid-nvidia-guest-prebuilts-v${version}.tar.zst";
    url = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}/waydroid-nvidia-guest-prebuilts-v${version}.tar.zst";
    hash = "sha256-YYmfVsIDt1DUH3wUGh7iZMtoJBdIzJzaUS7UXymXy9E=";
  };
in
stdenv.mkDerivation {
  pname = "guest-prebuilts-nvidia";
  inherit version;

  src = tarball;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zstd ];

  installPhase = ''
    mkdir -p $out/lib/waydroid-nvidia/guest
    tar --zstd -xf "$src" -C $out/lib/waydroid-nvidia/guest --strip-components=1
  '';

  meta = {
    description = "Prebuilt guest components for waydroid-nvidia (hwcomposer, ANGLE, surfaceflinger)";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
