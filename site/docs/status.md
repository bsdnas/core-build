# Project status

Last updated: August 2026.

This page exists so that nobody has to guess how far along the project is. It
lists what has been done, what is being worked on, and what has explicitly not
been tested.

## Done

* **The build runs end to end** from the project's own repositories on FreeBSD
  `stable/15` and produces an installable ISO.
* **Installation works** — verified by an automated acceptance run that
  installs in a virtual machine and checks the result through the API.
* **Upgrade from official TrueNAS CORE 13.3-U1.2 works** and preserves pools,
  datasets, shares, users, passwords and iocage jails. See
  [Upgrading](upgrade.md).
* **Containers work.** `podman` with `ocijail` runs FreeBSD images and, via
  FreeBSD's Linux emulation, Linux images too. That required fixing the kernel
  module list: `linux64.ko` shipped but could not load because its dependency
  `mqueuefs` was never built.
* **A configuration-loss bug was found and fixed.** The stock installer copied
  the preserved configuration into `/tmp`, which is a 5 MB tmpfs, and copied a
  24 MB package database and 93 MB of kernel modules into it before deleting
  them. The copy failed with `No space left on device`, and the failure was not
  checked — the upgrade continued and silently produced a system with a default
  configuration. The fix checks every copy and verifies the configuration
  database by checksum.
* **Upstream tracking is automated** — four watchers, running weekly.
* **First public build released** — see [Download](download.md), signed with
  the project key.
* **Updates without boot media work.** The project runs its own update train:
  an installed system finds the new build, downloads it, applies it and
  reboots. Measured end to end on the stand — the system came back on the new
  version in about three minutes.
* **Legal cleanup** — files covered by the TrueNAS Enterprise licence were
  removed at the outset; branding is the project's own.

## In progress

* [Containers](containers.md) — `podman` and `ocijail` ship in the image and
  both FreeBSD and Linux containers run, verified on a freshly installed image.
  What is missing is integration: no web interface, no acceptance coverage.

## Not done, and honestly so

* The published build is a development build rather than a stable release.
  It is signed, but the signing key lives on a workstation rather than a
  hardware token.
* **Update manifests are not signed.** The update client fetches them over
  HTTPS and verifies each package against the checksum in the manifest, so a
  corrupted download is caught — but the manifest itself is trusted on the
  strength of TLS alone. Signing it is the next step there.
* **One test machine.** Every measurement on this site comes from the same
  virtual stand. No physical hardware, no varied disk controllers, no real
  workloads.
* **Untested configurations:** HA (dual controller) systems, GELI encryption,
  iSCSI under load, Active Directory authentication, raidz pools, separate
  cache and log devices.
* **No upgrade path from anything older than 13.3.**
* **No security audit.** The project inherits whatever the upstream sources
  contain.

## How claims here are made

Every statement on this site is either a measurement or is marked as untested.
When something was verified, the project's journal records the command, the
output and the date. When a previous claim turned out to be wrong — as happened
with the reversibility of `zpool upgrade` — the correction is recorded next to
the original rather than quietly replacing it.

That is deliberate. A fork that overstates what it has tested is worse than no
fork at all, because people put data on it.
