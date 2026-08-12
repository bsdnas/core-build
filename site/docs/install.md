# Installing

!!! info "Development build"
    The published image is an early development build — get it from the
    [Download](download.md) page, or build one yourself from
    [source](building.md).

## Requirements

The same hardware requirements as TrueNAS CORE 13.3, because it is the same
system on a newer base:

* 64-bit x86 processor
* 8 GB RAM (the installer warns below 7 GB but continues)
* a dedicated boot device — the installer takes the whole device
* separate disks for storage; do not put pools on the boot device

The build targets `amd64` only. There is no ARM image.

## Fresh install

1. Write the image to a USB stick or attach it as virtual media.
2. Boot from it and choose `Install/Upgrade`.
3. Select the boot device and confirm the format.
4. Set the root password.
5. Choose BIOS or UEFI boot to match how the machine boots.
6. Remove the media and boot from disk.

The console then shows the usual menu with the web interface address. Log in as
`root` with the password you set.

## Virtual machines

The build runs under bhyve, KVM/QEMU and Proxmox. Note that the VMware and Xen
guest additions are **not** included at the moment — those ports do not compile
on FreeBSD 15 with the current compiler — so under those hypervisors you lose
time synchronisation and graceful shutdown from the hypervisor side.

For a pass-through storage controller the usual advice applies: give the
virtual machine the controller itself, not virtual disks carved out of a
datastore.

## Checking the result

```
# uname -a                      # should report 15.x-STABLE
# zpool status                  # pools present and healthy
# midclt call system.state      # should print "READY"
```

The project ships the same check as an automated acceptance run —
`tools/acceptance.sh` in the build repository drives an installation in a
virtual machine and verifies the result through the API. It is what every claim
on this site was measured with.
