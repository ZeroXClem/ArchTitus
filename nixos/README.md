# ArchTitus disk layout for NixOS

`disko-archtitus.nix` reproduces the on-disk layout that
`scripts/0-preinstall.sh` builds, expressed declaratively for NixOS via
[disko](https://github.com/nix-community/disko).

It exists so a NixOS box — a Proxmox VM or bare metal — comes up with a disk
that looks exactly like an ArchTitus install: same GPT partitioning, same btrfs
subvolumes, same mount options.

This is a **companion artifact, not an installer backend.** ArchTitus stays an
Arch installer. NixOS is provisioned by its own tooling; all this does is make
the two agree on disk layout.

## What it reproduces

| ArchTitus (`0-preinstall.sh`)                | Here                                        |
|----------------------------------------------|---------------------------------------------|
| `sgdisk` p1 `+1M` `ef02` BIOSBOOT            | `BIOSBOOT`, 1M, type `EF02`                 |
| `sgdisk` p2 `+300M` `ef00` EFIBOOT           | `EFIBOOT`, 300M, `EF00`, vfat → `/boot`     |
| `sgdisk` p3 rest `8300` ROOT                 | `ROOT`, 100%                                |
| `FS=luks` → cryptsetup, `/dev/mapper/ROOT`   | `luks` wrapper, `name = "ROOT"`             |
| `mkfs.btrfs -L ROOT`                         | `extraArgs = [ "-L" "ROOT" "-f" ]`          |
| `@ @home @var @tmp @.snapshots`              | same five subvolumes                        |
| `drivessd()` mount options                   | `ssd` argument toggles the `ssd` option     |
| `/opt/swap` swapfile with `chattr +C`        | optional `@swap` subvolume (disko does NOCOW) |

## Usage

```nix
imports = [
  inputs.disko.nixosModules.disko
  (import ./disko-archtitus.nix {
    device   = "/dev/nvme0n1";  # REQUIRED — check `lsblk` first
    luks     = true;            # LUKS2 on root
    ssd      = true;            # adds the `ssd` mount option
    swapSize = "8G";            # null to skip the swapfile
  })
];
```

Then let [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere)
drive it, or run disko directly:

```bash
nix run github:nix-community/disko -- --mode disko ./disko-archtitus.nix
```

> **`--mode disko` ZAPS the target device**, the same way `sgdisk -Z` does in
> `0-preinstall.sh`, and it does not prompt for confirmation. Check `device`
> twice.

Omitting `device` throws a descriptive error rather than silently defaulting to
some other disk.

## Verified

Evaluated against the real disko module inside a full NixOS eval. The generated
`fileSystems`, `swapDevices` and `boot.initrd.luks.devices` all resolve
correctly:

```
subvolumes   @  @.snapshots  @home  @swap  @tmp  @var
fileSystems  /  /.snapshots  /boot  /home  /swap  /tmp  /var
luksDevices  ROOT
swapDevices  /swap/swapfile
```
