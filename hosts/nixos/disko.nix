{ diskDevice ? throw "Pass --argstr diskDevice /dev/disk/by-id/<system-disk>", ... }:
{
  # Destructive installation layout.  The filesystem UUIDs intentionally match
  # hardware-configuration.nix so a freshly partitioned machine boots with the
  # same host configuration without regenerating or committing hardware files.
  disko.devices.disk.system = {
    type = "disk";
    device = diskDevice;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "1G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
            extraArgs = [ "-i" "A3B05758" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            extraArgs = [ "-U" "3c50b4f8-57e8-43c3-a8a5-21a5b829a366" ];
          };
        };
      };
    };
  };
}
