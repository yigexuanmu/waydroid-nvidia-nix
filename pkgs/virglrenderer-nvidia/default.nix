{
  lib
, stdenv
, meson
, ninja
, pkg-config
, python3
, python3Packages
, libepoxy
, libdrm
, libgbm
, libX11
, expat
, vulkan-headers
, vulkan-loader
, wayland
}:

let
  pname = "virglrenderer-nvidia";
  version = "0.1.1";

  # Pinned upstream commit from packaging/ci/pins.env
  src = builtins.fetchGit {
    url = "https://gitlab.freedesktop.org/virgl/virglrenderer.git";
    rev = "dc35e4db03144f81637c5ad061f61d3334b078fe";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  patches = [
    ./../../patches/virglrenderer/0001-vtest-support-exporting-sync_file-fds-for-venus-sync.patch
    ./../../patches/virglrenderer/0002-vtest-support-importing-dmabufs-as-blob-resources-fo.patch
    ./../../patches/virglrenderer/0003-vtest-raise-listen-backlog-to-128.patch
    ./../../patches/virglrenderer/0004-wip-gpu-alloc-and-global-priority.patch
  ];

  postPatch = ''
    cp ${./../../src/virglrenderer-vtest/vtest_gpu_alloc.c} vtest/vtest_gpu_alloc.c
    cp ${./../../src/virglrenderer-vtest/vtest_gpu_alloc.h} vtest/vtest_gpu_alloc.h
    cp ${./../../src/vtest_alloc_formats.h} vtest/vtest_alloc_formats.h
  '';

  nativeBuildInputs = [ meson ninja pkg-config python3 python3Packages.pyyaml ];

  buildInputs = [ libepoxy libdrm libgbm libX11 expat vulkan-headers vulkan-loader wayland ];

  mesonFlags = [
    "-Dvenus=true"
    "-Drender-server-worker=auto"
  ];

  postInstall = ''
    mkdir -p $out/lib/waydroid-nvidia
    mv $out/bin/virgl_test_server $out/lib/waydroid-nvidia/
    mv $out/libexec/virgl_render_server $out/lib/waydroid-nvidia/ 2>/dev/null || \
      mv $out/bin/virgl_render_server $out/lib/waydroid-nvidia/
    cp -L $out/lib/libvirglrenderer.so.1 $out/lib/waydroid-nvidia/
    rm -rf $out/bin $out/libexec
  '';

  meta = {
    description = "Patched virglrenderer for NVIDIA GPU acceleration in Waydroid";
    homepage = "https://github.com/Shiro836/waydroid-nvidia";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
