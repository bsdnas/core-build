# Download

**[BSDnas v0.1.0-dev](https://github.com/bsdnas/core-build/releases/tag/v0.1.0-dev)** —
installable ISO, 1.2 GB.

!!! warning "Development build"
    This is the first public build. It has been verified on a single virtual
    test machine and nowhere else — no physical hardware, no varied controllers,
    no real workloads. Treat it accordingly: do not put your only copy of
    anything on it, and keep a configuration backup.

## Verify what you downloaded

The release includes `SHA256SUMS` and a detached OpenPGP signature over it.
Checking the checksum alone only tells you the download is not corrupted —
anyone able to replace the image can replace the checksum file too. Check the
signature as well.

```
gpg --import BSDnas-signing-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

Expected: a good signature from `BSDnas release signing <bsd@22r.tech>`, then
`BSDnas-15-MASTER-202608102057.iso: OK`.

Signing key fingerprint — compare it with the copy on this page, which is
served over a different path than the release itself:

```
5852 8D1C DBDA AF7B 01ED  2BBE 1E2F 7A79 2066 322D
```

The key is also available here: [BSDnas-signing-key.asc](BSDnas-signing-key.asc).

**What this does and does not protect against.** The signature proves the
checksum file came from the holder of that key. The secret key lives in the
maintainer's offline key store; its handling is
not documented here. That defends against the key file leaking on
its own — an accidental copy into a repository, a backup, a shared archive — but
not against that workstation being compromised. A hardware token is the next
step and has not been taken yet.

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
