# ArchTitus disk layout, expressed declaratively for NixOS via disko.
#
# This is a companion artifact, not part of the Arch installer. It reproduces
# the exact on-disk layout that scripts/0-preinstall.sh builds -- same GPT
# partitioning, same btrfs subvolumes, same mount options -- so a NixOS machine
# (Proxmox VM or bare metal) lands with a disk that looks identical to an
# ArchTitus box.
#
# Usage in configuration.nix:
#
#     imports = [
#       inputs.disko.nixosModules.disko
#       (import ./disko-archtitus.nix {
#         device   = "/dev/nvme0n1";   # REQUIRED. Check with `lsblk` first.
#         luks     = true;             # LUKS2 on root, like FS=luks
#         ssd      = true;             # adds the `ssd` mount option
#         swapSize = "8G";             # null to skip the swapfile
#       })
#     ];
#
# Then either let nixos-anywhere drive it, or run disko directly:
#
#     nix run github:nix-community/disko -- --mode disko ./disko-archtitus.nix
#
# WARNING: `--mode disko` ZAPS the target device, exactly like `sgdisk -Z` does
# in 0-preinstall.sh. There is no confirmation prompt. Check `device` twice.

{
  device ? throw "disko-archtitus.nix: you must pass `device`, e.g. \"/dev/nvme0n1\"",
  luks ? false,
  ssd ? true,
  swapSize ? null,
}:

let
  # Mirrors drivessd() in scripts/startup.sh, which sets:
  #   ssd  -> noatime,compress=zstd,ssd,commit=120
  #   hdd  -> noatime,compress=zstd,commit=120
  mountOptions =
    [ "noatime" "compress=zstd" ]
    ++ (if ssd then [ "ssd" ] else [ ])
    ++ [ "commit=120" ];

  # The five subvolumes created by createsubvolumes() in 0-preinstall.sh.
  # @ is root; the rest are mounted by mountallsubvol().
  subvolumes = {
    "@" = {
      mountpoint = "/";
      inherit mountOptions;
    };
    "@home" = {
      mountpoint = "/home";
      inherit mountOptions;
    };
    "@var" = {
      mountpoint = "/var";
      inherit mountOptions;
    };
    "@tmp" = {
      mountpoint = "/tmp";
      inherit mountOptions;
    };
    # Kept as its own subvolume so snapshots are never themselves snapshotted --
    # same reason configs/etc/snapper/configs/root wants it separate.
    "@.snapshots" = {
      mountpoint = "/.snapshots";
      inherit mountOptions;
    };
  }
  # 0-preinstall.sh puts its swapfile in /opt/swap with chattr +C. disko handles
  # the NOCOW requirement itself when a swapfile is declared on btrfs.
  // (if swapSize != null then {
    "@swap" = {
      mountpoint = "/swap";
      swap.swapfile.size = swapSize;
    };
  } else { });

  btrfsContent = {
    type = "btrfs";
    # -L ROOT matches `mkfs.btrfs -L ROOT`; -f forces over any existing signature.
    extraArgs = [ "-L" "ROOT" "-f" ];
    inherit subvolumes;
  };

  rootContent =
    if luks then {
      type = "luks";
      name = "ROOT"; # opens at /dev/mapper/ROOT, as the GRUB cmdline expects
      settings = {
        allowDiscards = true;
      };
      content = btrfsContent;
    } else btrfsContent;
in
{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT'
        # Kept so the same layout boots on legacy BIOS as well as UEFI.
        BIOSBOOT = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };

        # sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFIBOOT'
        EFIBOOT = {
          priority = 2;
          size = "300M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # Keeps the unencrypted ESP from being world-readable, which
            # systemd-boot and recent NixOS both warn about otherwise.
            mountOptions = [ "umask=0077" ];
          };
        };

        # sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT'
        ROOT = {
          priority = 3;
          size = "100%";
          content = rootContent;
        };
      };
    };
  };
}
