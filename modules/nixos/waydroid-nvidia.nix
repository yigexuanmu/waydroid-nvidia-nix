{
  config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.waydroid-nvidia;
  wnv = cfg.package;

  # The unit file this module generates; systemd.user.units.<name>.unit is the
  # store *directory* that contains it.
  venusUnitPath = "${config.systemd.user.units."wd-venus.service".unit}/wd-venus.service";

  # Keep each desktop user's own copy of that unit a live link to it. See the
  # comment on systemd.tmpfiles.rules below for why this is needed.
  userUnitPins = user:
    let
      u = config.users.users.${user};
      group = if u.group == null then "root" else u.group;
      base = "${u.home}/.config";
    in
    lib.optionals (u.home != null && u.home != "/var/empty") (
      # mode "-" so an existing directory keeps its own mode while a missing one
      # is created owned by the user.
      map (d: "d ${d} - ${user} ${group} -") [
        base
        "${base}/systemd"
        "${base}/systemd/user"
        "${base}/systemd/user/default.target.wants"
      ]
      ++ map (p: "L+ ${p} - - - - ${venusUnitPath}") [
        "${base}/systemd/user/wd-venus.service"
        "${base}/systemd/user/default.target.wants/wd-venus.service"
      ]
    );
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

    desktopUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.mapAttrsToList (n: _: n)
          (lib.filterAttrs (_: u:
            u.isNormalUser && u.home != null && u.home != "/var/empty")
            config.users.users);
      defaultText =
        lib.literalExpression "every user with isNormalUser = true and a real home directory";
      description = ''
        Users whose ~/.config/systemd/user/wd-venus.service (and its
        default.target.wants link) is pinned to the unit this module generates.

        Leave this at the default unless a user's home directory is not on
        local storage or must not be touched by systemd-tmpfiles.
      '';
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

    # Pin the user-level unit, and keep it pinned.
    #
    # systemd resolves a per-user unit from, in this order:
    # ~/.config/systemd/user, /etc/systemd/user, $XDG_DATA_DIRS/systemd/user.
    # A file in the first directory therefore *shadows* the one this module
    # installs in /etc/systemd/user.
    #
    # The documented one-liner `systemctl --user enable --now wd-venus.service`
    # (README, install-manual, waydroid-nvidia-setup, and the error message of
    # the waydroid patch) materialises exactly such a file: a permanent symlink
    # in ~/.config/systemd/user pointing at the unit's /nix/store path. That path
    # is generation-scoped, so the next rebuild that changes the unit — or a
    # garbage collection — leaves a dangling link, which shadows the still valid
    # /etc unit. systemd then reports wd-venus.service as "bad" or missing
    # ("Unit wd-venus.service does not exist"), the Venus socket is never
    # created, and waydroid fails its socket preflight.
    #
    # Declaring the two paths here makes the module own them: systemd-tmpfiles
    # rewrites them from the current system closure on every boot, so they cannot
    # go stale, and the closure keeps the target alive across GC. Enabling the
    # unit by hand is unnecessary anyway — wantedBy = [ "default.target" ] above
    # already starts it with the user manager.
    systemd.tmpfiles.rules = lib.concatMap userUnitPins cfg.desktopUsers;

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
