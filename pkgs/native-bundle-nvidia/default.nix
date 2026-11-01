# The CI-built release bundle of the nvidia-prolapse (default) driver mode: the Mesa NVK +
# Rust RM payload, the install-time gate programs and the glibc-shim tree, laid out as
# packaging/native/collect.py produced it. waydroid-nvidia-full unpacks it with upstream's own
# packaging/native/install-native.sh, which verifies every file against BUILD-RECORD.json.
{ fetchurl }:

let
  version = "0.2.0";
in
fetchurl {
  name = "waydroid-nvidia-native-x86_64-v${version}.tar.zst";
  url = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}/waydroid-nvidia-native-x86_64-v${version}.tar.zst";
  hash = "sha256-M8n3X6IWxTgo6T6PsqTmNWLjqyeyTIEmiHnuSDkPzPg=";
}
