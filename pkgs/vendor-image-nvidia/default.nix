# The nvidia-prolapse vendor image as a Waydroid OTA zip, plus the OTA channel that names it
# (the setup verifies the zip's sha256 against the channel's id, exactly as Waydroid's own
# updater does). waydroid-nvidia-full ships both under lib/waydroid-nvidia/vendor; the image
# itself is installed into /var/lib/waydroid by `sudo waydroid-nvidia-setup`.
#
# A single output so the flake can expose it as a package: linkFarm links both release assets
# under their upstream file names without copying the 200 MB zip again.
{
  fetchurl
, linkFarm
}:

let
  version = "0.2.0";
  base = "https://github.com/Shiro836/waydroid-nvidia/releases/download/v${version}";
  imageName = "waydroid-nvidia-vendor-x86_64-v${version}.zip";
  channelName = "waydroid-nvidia-vendor-ota-v${version}.json";
in
linkFarm "waydroid-nvidia-vendor-x86_64-v${version}" [
  {
    name = imageName;
    path = fetchurl {
      name = imageName;
      url = "${base}/${imageName}";
      hash = "sha256-aSoO60XCiEkvZt26W3fqFfAPiOylNUsEjsSx51Ku4ps=";
    };
  }
  {
    name = channelName;
    path = fetchurl {
      name = channelName;
      url = "${base}/${channelName}";
      hash = "sha256-KUCgTXG6JuMvhexyI7GTRKicueyq/eSnFar5z/TuPGA=";
    };
  }
]
