{
  config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.waydroid-nvidia;
  wnv = cfg.package;
in
{
  options.services.waydroid-nvidia = {
    enable = lib.mkEnableOption "waydroid-nvidia GPU acceleration";

    package = lib.mkPackageOption pkgs "waydroid-nvidia-full" { };

    refreshRate = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Monitor refresh rate in Hz (e.g. 144, 240, 500)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wnv ];

    # waydroid-container.service (patched to use Nix paths, system unit only)
    systemd.services.waydroid-container = {
      description = "Waydroid Container";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        UMask = "0022";
        BusName = "id.waydro.Container";
        ExecStart = "${wnv}/bin/waydroid container start";
        Type = "dbus";
      };
    };

    # udev rule for /dev/udmabuf (uaccess for seated user)
    services.udev.packages = [ wnv ];

    # user service for Venus render server
    #
    # RuntimeDirectory=waydroid-venus makes systemd create
    # $XDG_RUNTIME_DIR/waydroid-venus at mode 0755 *inside the desktop user's
    # own 0700 runtime directory*. That is deliberate (upstream PR #20): the
    # previous shared, root-owned 1777 /run/waydroid-venus let any other local
    # user find the socket and drive the GPU. Keep this in sync with
    # packaging/aur/.../wd-venus.service and with the nvidia_venus_socket value
    # that waydroid-nvidia-setup writes into waydroid.cfg.
    systemd.user.services.wd-venus = {
      description = "Venus vtest render server for waydroid-nvidia";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        RuntimeDirectory = "waydroid-venus";
        ExecStart = "${wnv}/lib/waydroid-nvidia/virgl_test_server --venus --multi-clients --socket-path %t/waydroid-venus/venus.sock";
        Environment = [
          "RENDER_SERVER_EXEC_PATH=${wnv}/lib/waydroid-nvidia/virgl_render_server"
          "LD_LIBRARY_PATH=${wnv}/lib/waydroid-nvidia:${pkgs.vulkan-loader}/lib"
        ];
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # post-installation hint
    systemd.services.waydroid-nvidia-setup-warning = {
      description = "waydroid-nvidia setup reminder";
      before = [ "waydroid-container.service" ];
      wantedBy = [ "waydroid-container.service" ];
      script = ''
        if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
          echo "waydroid-nvidia: run 'waydroid init' then 'sudo waydroid-nvidia-setup${lib.optionalString (cfg.refreshRate != null) " --refresh ${toString cfg.refreshRate}"}'"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
