# Containers

**Status: works, not yet integrated.** Containers run — both FreeBSD and Linux
images — but they are managed from the command line; the web interface knows
nothing about them.

FreeBSD 15 ships a usable OCI stack — `podman` with `ocijail` as the runtime —
and BSDnas includes it. Containers here are jails underneath, not a virtual
machine with a Linux kernel.

## Verified on a running system

Checked on a freshly installed BSDnas image, not on a machine prepared by hand:

* `podman` and `ocijail` ship **in the image** — nothing to install afterwards;
* the kernel has `VIMAGE`, `racct` and `rctl` enabled;
* a FreeBSD container runs;
* a **Linux container runs** — `podman run --os=linux alpine` reports
  `PRETTY_NAME="Alpine Linux v3.24"`;
* `kldload linux64` succeeds, pulling in `mqueuefs` — see below for why that
  sentence exists.

## Linux images need one kernel module

Running Linux images relies on FreeBSD's Linux emulation, and that turned out
to be broken in the inherited configuration:

```
# podman run --rm --os=linux docker.io/library/alpine cat /etc/os-release
ocijail: error executing container command: Exec format error

# kldload linux64
KLD linux64.ko: depends on mqueuefs - not available or version mismatch
```

`linux64.ko` was present in the image but could not load, because its
dependency `mqueuefs` was not built. The module list inherited from TrueNAS
contains `linux`, `linux64`, `linux_common`, `linprocfs` and `linsysfs` — the
intent was there — but not `mqueuefs`. The other dependencies
(`sysvmsg`, `sysvsem`, `sysvshm`, `netlink`) are compiled into the kernel; that
one was not.

BSDnas adds the `mqueue` module to the kernel build. For a NAS this matters:
most useful container images are Linux images. Verified on the built image —
both modules load, and Linux containers run.

## Storage must go on a pool

`/var` on this system is a tmpfs. Podman's default store lives at
`/var/db/containers/storage`, which means it would live in RAM and disappear on
reboot.

Point the store at a dataset instead — `/usr/local/etc/containers/storage.conf`:

```ini
[storage]
driver = "zfs"
graphroot = "/mnt/tank/containers"
runroot = "/var/run/containers/storage"
```

with the dataset created beforehand:

```
# zfs create tank/containers
```

Note that pools are mounted under `altroot=/mnt`, so `zfs create -o
mountpoint=/var/db/containers/storage` does **not** produce the path you asked
for — it lands under `/mnt`. Use the dataset's natural mountpoint and point
`graphroot` at it.

## What is still missing

* No integration with the web interface. Containers are managed from the
  command line.
* No acceptance test covering containers, so nothing here is guaranteed to
  survive an upgrade.
* Linux emulation still needs to be enabled deliberately:
  `sysrc linux_enable=YES && service linux start`.
* Networking beyond the default bridge, port publishing and NAT have not been
  exercised.
