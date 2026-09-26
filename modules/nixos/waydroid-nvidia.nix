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

    # post-installation hint + stale-config guard.
    #
    # The venus socket moved to the desktop user's private runtime directory in
    # 0.1.3, but nvidia_venus_socket in waydroid.cfg is a runtime artifact that
    # only waydroid-nvidia-setup rewrites. After an upgrade the file can still
    # point at the retired shared /run/waydroid-venus path, and waydroid then
    # refuses to start with a misleading "not accepting connections" error.
    # Check the value itself, not merely whether the file exists.
    systemd.services.waydroid-nvidia-setup-warning = {
      description = "waydroid-nvidia setup reminder";
      before = [ "waydroid-container.service" ];
      wantedBy = [ "waydroid-container.service" ];
      script = ''
        CFG=/var/lib/waydroid/waydroid.cfg
        SETUP="sudo waydroid-nvidia-setup${lib.optionalString (cfg.refreshRate != null) " --refresh ${toString cfg.refreshRate}"}"

        if [ ! -f "$CFG" ]; then
          echo "waydroid-nvidia: run 'waydroid init' then '$SETUP'"
          exit 0
        fi

        SOCKET=$(grep -E '^[[:space:]]*nvidia_venus_socket[[:space:]]*=' "$CFG" \
                  | tail -1 | cut -d= -f2- | tr -d '[:space:]')

        if [ -z "$SOCKET" ]; then
          echo "waydroid-nvidia: $CFG has no nvidia_venus_socket; run '$SETUP'"
          exit 0
        fi

        case "$SOCKET" in
          /run/user/*/waydroid-venus/venus.sock)
            UID_NUM=$(printf '%s' "$SOCKET" | sed 's|^/run/user/||; s|/.*||')
            if [ ! -d "/run/user/$UID_NUM" ]; then
              echo "waydroid-nvidia: nvidia_venus_socket points at vanished session /run/user/$UID_NUM"
              echo "waydroid-nvidia: log in as that desktop user, or re-run '$SETUP'"
            fi
            ;;
          *)
            echo "waydroid-nvidia: STALE nvidia_venus_socket='$SOCKET'"
            echo "waydroid-nvidia: the venus socket is now per-user; re-run '$SETUP'"
            ;;
        esac
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
