# Download

**[BSDnas v0.1.0-dev](https://github.com/bsdnas/core-build/releases/tag/v0.1.0-dev)** —
installable ISO, 1.2 GB.

!!! warning "Development build"
    This is the first public build. It has been verified on a single virtual
    test machine and nowhere else — no physical hardware, no varied controllers,
    no real workloads. Treat it accordingly: do not put your only copy of
    anything on it, and keep a configuration backup.

## Verify what you downloaded

The release includes `SHA256SUMS`. Download both files into the same directory
and check:

```
sha256sum -c SHA256SUMS
```

Expected result: `BSDnas-15-MASTER-202608102057.iso: OK`.

A mismatch means the download is damaged or tampered with — do not install it.

The images are **not signed** yet. Signing is on the list; until then the
checksum only protects against a corrupted download, not against a compromised
mirror.

## What is in this build

| | |
|---|---|
| base | FreeBSD `stable/15` |
| OpenZFS | 2.4.3 |
| Samba | 4.23 |
| ports tree | FreeBSD quarterly `2026Q2` |
| containers | `podman`, `ocijail`, CNI plugins included |

## Next steps

* [Installing](install.md) — fresh installation
* [Upgrading from TrueNAS CORE](upgrade.md) — **read the `zpool upgrade`
  section before you upgrade a pool**
* [Containers](containers.md) — running FreeBSD and Linux images
* [Project status](status.md) — what is done, what is not, what was never tested

## Older builds

There are none. This is the first.
