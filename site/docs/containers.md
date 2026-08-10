# Containers

**Status: in progress.** Part of this is verified on a running system, part is
built but not yet verified. The two are marked separately below, because the
difference matters.

FreeBSD 15 ships a usable OCI stack — `podman` with `ocijail` as the runtime —
and BSDnas includes it. Containers here are jails underneath, not a virtual
machine with a Linux kernel.

## Verified on a running system

Checked live on a BSDnas installation:

* the kernel has `VIMAGE`, `racct` and `rctl` enabled — the prerequisites for
  container networking and resource limits;
* `podman` 5.8.4, `ocijail` 0.6.0 and `containernetworking-plugins` install and
  run;
* a FreeBSD container starts and runs.

## Built but not yet verified

`podman`, `ocijail` and `containernetworking-plugins` are now part of the image
rather than something you install afterwards, and the kernel module needed for
Linux images has been added. Neither has been through an acceptance run yet.

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
most useful container images are Linux images.

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
* Linux emulation is enabled by the kernel module but the userland Linux
  runtime (`linux_enable="YES"`) still needs to be turned on deliberately.
