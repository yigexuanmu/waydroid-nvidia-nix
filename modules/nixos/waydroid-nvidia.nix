{
  config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.waydroid-nvidia;
  wnv = cfg.package;

  # The driver mode lives in waydroid.cfg and is written by `waydroid-nvidia-setup`, which also
  # installs the mode's guest image. These options only describe the setup call and decide whether
  # this module starts the Venus socket server.
  setupFlags =
    lib.optional (cfg.mode != null) "--mode ${cfg.mode}"
    ++ lib.optional (cfg.nativeGl != null) "--native-gl ${cfg.nativeGl}"
    ++ lib.optional (cfg.refreshRate != null) "--refresh ${toString cfg.refreshRate}";
  setupCommand =
    "sudo waydroid-nvidia-setup${lib.optionalString (setupFlags != [ ]) " ${lib.concatStringsSep " " setupFlags}"}";

  # The Venus socket server is only used by the venus driver mode; nvidia-prolapse (upstream's
  # default) and glibc-shim talk to the driver directly. With no mode configured we keep it running,
  # so a venus setup configured by an earlier version of this flake keeps working.
  wantVenus = cfg.mode == null || cfg.mode == "venus";
in
{
  options.services.waydroid-nvidia = {
    enable = lib.mkEnableOption "waydroid-nvidia GPU acceleration";

    package = lib.mkPackageOption pkgs "waydroid-nvidia-full" { };

    mode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "nvidia-prolapse"
          "glibc-shim"
          "venus"
        ]
      );
      default = null;
      description = ''
        Driver mode passed to `waydroid-nvidia-setup`: `nvidia-prolapse` (upstream's default: the
        release's own vendor image with Mesa NVK, no host driver involved), `glibc-shim` (the host's
        NVIDIA driver inside Android) or `venus` (Vulkan over a socket to the host, needs the open
        kernel module).
        When null, whatever waydroid.cfg already says is kept; a fresh install gets upstream's
        default.
      '';
    };

    nativeGl = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "on"
          "off"
        ]
      );
      default = null;
      description = ''
        Use the mode's own GL driver instead of ANGLE (`--native-gl`): our `nvrm` in
        `nvidia-prolapse`, NVIDIA's own GLES in `glibc-shim`. Not available in `venus`.
        When null, the value already in waydroid.cfg is kept (off for a fresh install).
      '';
    };

    refreshRate = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Override the display refresh rate hwcomposer reports, in Hz (e.g. 144, 240). Null leaves
        upstream's behaviour: the fastest current mode of the outputs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wnv ];

    # Waydroid needs binder; the nixpkgs waydroid module asks for the same module.
    boot.kernelModules = [ "binder_linux" ];

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

    # udev rules: /dev/udmabuf uaccess for the seated user and the NVIDIA render node as the
    # systemd device unit the container unit waits for at boot
    services.udev.packages = [ wnv ];

    # tmpfiles.d for /run/waydroid-venus socket directory
    systemd.tmpfiles.packages = [ wnv ];

    # user service for the Venus vtest render server
    systemd.user.services.wd-venus = lib.mkIf wantVenus {
      description = "Venus vtest render server for waydroid-nvidia";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${wnv}/lib/waydroid-nvidia/virgl_test_server --venus --multi-clients --socket-path /run/waydroid-venus/venus.sock";
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
          echo "waydroid-nvidia: run '${setupCommand}' (it also runs 'waydroid init' for you), and again after every NVIDIA driver update"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
