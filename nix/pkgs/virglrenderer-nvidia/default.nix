{
  lib
, stdenv
, meson
, ninja
, pkg-config
, python3
, libepoxy
, libdrm
, libX11
, expat
, vulkan-loader
, wayland
, wnv-src
}:

let
  pname = "virglrenderer-nvidia";
  version = "0.1.0-rc3";

  # Pinned upstream commit from packaging/ci/pins.env
  src = builtins.fetchGit {
    url = "https://gitlab.freedesktop.org/virgl/virglrenderer.git";
    rev = "dc35e4db03144f81637c5ad061f61d3334b078fe";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  patches = [
    "${wnv-src}/patches/virglrenderer/0001-vtest-support-exporting-sync_file-fds-for-venus-sync.patch"
    "${wnv-src}/patches/virglrenderer/0002-vtest-support-importing-dmabufs-as-blob-resources-fo.patch"
    "${wnv-src}/patches/virglrenderer/0003-vtest-raise-listen-backlog-to-128.patch"
    "${wnv-src}/patches/virglrenderer/0004-wip-gpu-alloc-and-global-priority.patch"
  ];

  postPatch = ''
    cp ${wnv-src}/src/virglrenderer-vtest/vtest_gpu_alloc.c vtest/
    cp ${wnv-src}/src/virglrenderer-vtest/vtest_gpu_alloc.h vtest/
  '';

  nativeBuildInputs = [ meson ninja pkg-config python3 ];

  buildInputs = [ libepoxy libdrm libX11 expat vulkan-loader wayland ];

  mesonFlags = [
    "-Dvenus=true"
    "-Drender-server-worker=auto"
  ];

  postInstall = ''
    mkdir -p $out/lib/waydroid-nvidia
    mv $out/bin/virgl_test_server $out/lib/waydroid-nvidia/
    mv $out/bin/virgl_render_server $out/lib/waydroid-nvidia/
    mv $out/lib/libvirglrenderer.so.1 $out/lib/waydroid-nvidia/
    rm -rf $out/bin
  '';

  meta = {
    description = "Patched virglrenderer for NVIDIA GPU acceleration in Waydroid";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
