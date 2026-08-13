# Installing

!!! info "Development build"
    The published image is an early development build — get it from the
    [Download](download.md) page, or build one yourself from
    [source](building.md).

## Requirements

Do not confuse these with the requirements for *building* BSDnas — a build host
needs far more memory and disk. This page is about running the system.

* 64-bit x86 processor (`amd64` only; there is no ARM image)
* a dedicated boot device — the installer takes the whole device
* separate disks for storage; do not put pools on the boot device

### Memory

**Measured, not inherited from anyone's recommendation:**

| RAM | result |
|---|---|
| 8 GB | boots, reaches `READY`; the idle system uses under 2 GB |
| 4 GB | boots, reaches `READY` in 40 seconds |
| 2 GB | boots, reaches `READY` in 40 seconds |

The installer warns below 7 GB and continues; that warning is inherited from
TrueNAS and does not reflect what the system needs to run.

**4 GB is enough for the system to boot and run.** That is the honest floor,
and it is worth understanding what the rest of the memory is actually for:

* **ZFS ARC** — the read cache. ZFS will use whatever is free, and this is
  where extra memory turns into throughput. A machine with 4 GB works; a
  machine with 32 GB serves the same files faster because more of them are
  in RAM.
* **Working processes** — SMB and NFS sessions, jails, containers, replication
  and scrubs all take memory in proportion to what you actually run.
* **Deduplication** — if you enable it, it needs a great deal of RAM and is a
  different conversation entirely.

So the number to plan by comes from the workload, not from the boot
requirement. The figures in the table were measured on an idle system with no
pool under load: they tell you what it takes to start, not what it takes to
serve.

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
