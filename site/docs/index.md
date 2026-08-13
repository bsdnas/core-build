# BSDnas

**A community fork that continues TrueNAS CORE on current FreeBSD.**

TrueNAS CORE stopped at 13.3, on FreeBSD 13.3 — a release that has since been
removed from the FreeBSD mirrors. BSDnas moves that system onto FreeBSD
`stable/15` and keeps it there: new FreeBSD releases, security advisories and
OpenZFS versions are tracked continuously rather than in one heroic jump every
few years.

!!! warning "Read this before you install anything"
    This is an early project. One person maintains it. Everything described
    here has been measured on a test machine, and nothing has been measured
    anywhere else. Do not put your only copy of anything on it.

    The first build is available on the [Download](download.md) page.

## What actually works

Verified on a test stand, not claimed from theory:

| | |
|---|---|
| Builds reproducibly from source | yes, on FreeBSD stable/15 |
| Installs from ISO | yes |
| Upgrades an existing TrueNAS CORE 13.3 install | yes, config preserved |
| Pools created by OpenZFS 2.2 | import and work on 2.4.3 |
| SMB shares, users, passwords from 13.3 | preserved |
| iocage jails with 13.3 userland | run on the FreeBSD 15 kernel |
| OCI containers, FreeBSD and Linux images | run from the command line |
| Updating without boot media | works, through the project's update train |

A single upgrade run moves the system from FreeBSD 13.3 to stable/15, OpenZFS
2.2 to 2.4.3, Samba 4.20 to 4.23, and the ports Python from 3.9 to 3.11. On the
test stand it takes about fifteen minutes.

See [Upgrading](upgrade.md) for the procedure and the caveats — particularly
the one about `zpool upgrade`, which is worth reading *before* you run it.

## What does not work yet

Honesty is cheaper than support tickets:

* The published image is a **development build** — see [Download](download.md).
  It is signed, but verified on one virtual machine only.
* The SSH service does not start by itself after an upgrade; enable it again.
* The iocage plugin index is no longer maintained upstream, so plugins must
  come from your own index or be installed by hand.
* Hardware RAID utilities (`arcconf`, `megacli`, `tw_cli`) are not included:
  their vendors withdrew the distribution files. On a ZFS system hardware RAID
  is inadvisable anyway.
* VMware and Xen guest additions are currently absent — those ports do not
  compile on FreeBSD 15 with the current compiler.
* [Containers](containers.md) run, but only from the command line — the web
  interface knows nothing about them.
* Update manifests are served over HTTPS but are **not cryptographically
  signed** yet; package integrity is checked by checksum from the manifest.

## Why this exists

A fork rots when nobody moves it forward. The gap between TrueNAS CORE 13.3 and
current FreeBSD did not open because of any hard technical problem — it opened
because for a year nobody rebased the patches.

So the project is built around that failure mode. The FreeBSD patch set is
carried as a **rebased** series rather than a merge history, an
[upstream watcher](https://github.com/bsdnas/core-build/blob/bsdnas/tools/watch-upstream.sh)
reports every week what has moved (FreeBSD base, security advisories, the
quarterly ports branch, OpenZFS), and every claim on this site comes with the
measurement behind it.

## Not affiliated with iXsystems

BSDnas is an independent fork. It is not produced, endorsed or supported by
iXsystems, Inc. TrueNAS is their trademark. The middleware this project builds
on is LGPL-3.0; files covered by the TrueNAS Enterprise licence were removed
from the fork at the outset.
