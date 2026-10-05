{ config, lib, ... }:
{
  # P14s Gen 5 exposes s2idle, not S3. Keep a persistent image for S4 instead.
  # 40 GiB covers the 32 GiB RAM image plus ordinary swap use.
  swapDevices = [ {
    device = "/var/lib/hibernate.swap";
    size = 40 * 1024;
  } ];

  # systemd records the swapfile's device/offset in HibernateLocation (UEFI).
  # Its initrd generator reads that location before mounting the root filesystem.
  # Do not pin resume_offset: relocating/recreating the file would invalidate it.
  boot.initrd.systemd.enable = true;
  systemd.sleep.settings.Sleep = {
    AllowHibernation = true;
    HibernateMode = "platform";
  };

  services.logind.settings.Login = {
    SleepOperation = "hibernate";
    HandleSuspendKey = "hibernate";
    HandleHibernateKey = "hibernate";
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
    # Retain the usual docked/external-monitor behavior.
    HandleLidSwitchDocked = "ignore";
  };

  # Some desktops call Suspend() rather than the generic Sleep() operation.
  # Preserve the upstream unit's dependencies/locking while executing a proper
  # hibernate operation, including swap discovery and EFI resume information.
  # SuspendState=disk alone would bypass that hibernation preparation.
  systemd.services.systemd-suspend = {
    overrideStrategy = "asDropin";
    restartIfChanged = false;
    serviceConfig.ExecStart = [
      ""
      "${config.systemd.package}/lib/systemd/systemd-sleep hibernate"
    ];
  };

  assertions = [ {
    assertion = config.boot.resumeDevice == ""
      && !(lib.any (p: lib.hasPrefix "resume=" p || lib.hasPrefix "resume_offset=" p)
        config.boot.kernelParams);
    message = "S4 uses UEFI HibernateLocation; remove static resume/resume_offset overrides.";
  } {
    assertion = config.boot.initrd.systemd.package.withEfi;
    message = "S4 swapfile recovery requires an EFI-enabled systemd initrd.";
  } ];
}
