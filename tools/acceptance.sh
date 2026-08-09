#!/usr/bin/env bash
#
# Automated acceptance of a bsdnas image: install the system from an ISO and
# check that it really works, not merely that it built.
#
# The manual cycle this script replaces was walked through a dozen and a half
# times while debugging, and each pass cost about an hour of attention. Every
# technique here has already been shaken out live: typing into the installer
# with QEMU sendkey, screen capture with screendump, checks over the REST API.
#
# Usage:
#   acceptance.sh install <iso>            clean installation and checks
#   acceptance.sh upgrade <iso>            upgrade over the current system
#   acceptance.sh verify                   checks only, no installation
#   acceptance.sh snapshot <name>          take a rollback point
#   acceptance.sh rollback <name>          return the bench to a rollback point
#
# Environment variables (the defaults describe a test bench):
#   PVE      ssh address of the hypervisor     root@proxmox.example
#   VMID     the test virtual machine          100
#   NASIP    address of the running system     nas.example
#   NASPW    root password                     REDACTED
#   STORAGE  the storage holding the ISO       nfs-example

set -u

PVE="${PVE:-root@proxmox.example}"
VMID="${VMID:-147}"
NASIP="${NASIP:-nas.example}"
NASPW="${NASPW:-REDACTED}"
STORAGE="${STORAGE:-nfs-kmdz}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"

log()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '%s  FAILED: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

pve()      { timeout 120 $SSH "$PVE" "$@"; }
key()      { pve "printf 'sendkey $1\n' | qm monitor $VMID >/dev/null 2>&1"; }
# Type a string without Enter: passwords and input fields
text()     { pve "bash /tmp/sendtext.sh $VMID '$1'"; }
api()      { pve "timeout 30 curl -sk -u root:$NASPW https://$NASIP/api/v2.0/$1" 2>/dev/null; }

# Wait until middleware answers READY. Longer than it seems to be needed:
# after an upgrade the database migrations run.
wait_ready() {
    local _t=0
    while [ "$_t" -lt "${1:-600}" ]; do
        if [ "$(api system/state)" = '"READY"' ]; then
            log "system is ready (${_t}s)"
            return 0
        fi
        sleep 20; _t=$((_t + 20))
    done
    return 1
}

snapshot() { pve "qm snapshot $VMID $1 --description 'acceptance'" >/dev/null 2>&1 && log "snapshot $1 taken"; }

rollback() {
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6; qm rollback $VMID $1" >/dev/null 2>&1 || fail "the rollback to $1 failed"
    pve "qm set $VMID --boot order=scsi0 >/dev/null 2>&1; qm start $VMID" >/dev/null 2>&1
    log "bench returned to point $1"
}

boot_iso() {
    local _iso="$1"
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    # the boot order is set by a SEPARATE command: Proxmox rebuilds it when a
    # medium is attached within the same command and puts the disk first
    pve "qm set $VMID --ide2 $STORAGE:iso/$_iso,media=cdrom" >/dev/null 2>&1
    pve "qm set $VMID --boot order=ide2" >/dev/null 2>&1
    pve "qm start $VMID" >/dev/null 2>&1
    log "booting from $_iso"
    sleep 200
}

boot_disk() {
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    pve "qm set $VMID --ide2 none,media=cdrom" >/dev/null 2>&1
    pve "qm set $VMID --boot order=scsi0" >/dev/null 2>&1
    pve "qm start $VMID" >/dev/null 2>&1
    log "booting from the disk"
}

# Walking through the installer. mode: fresh | upgrade
run_installer() {
    local _mode="$1"
    key ret;  sleep 12          # Install/Upgrade
    key spc;  sleep 3
    key ret;  sleep 16          # disk da0 selected
    if [ "$_mode" = upgrade ]; then
        key ret; sleep 16       # Upgrade Install
        key ret; sleep 18       # Install in new boot environment
        key ret; sleep 500      # confirmation + installation
    else
        key right; sleep 3; key ret; sleep 14   # Fresh Install
        key right; sleep 3; key ret; sleep 14   # Format the boot device
        key ret;  sleep 14                      # confirmation
        text "$NASPW"; sleep 3                  # password
        key tab;  sleep 3
        text "$NASPW"; sleep 3
        key ret;  sleep 14
        key ret;  sleep 420                     # Boot via BIOS + installation
    fi
    key ret; sleep 8            # OK on the final window
}

# Checks on the live system. Exactly what tells "it built" from "it works".
verify() {
    local _rc=0 _v _pools _shares _shell

    wait_ready 900 || fail "the system never reached the READY state"

    _v=$(api system/version)
    log "version: $_v"

    _pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shell=$(api user | python3 -c '
import json,sys
for u in json.load(sys.stdin):
    if u.get("username") == "root":
        print(u.get("shell"))' 2>/dev/null)

    log "pools: ${_pools:-?}, shares: ${_shares:-?}, root shell: ${_shell:-?}"

    # The shell /usr/bin/zsh does not exist on FreeBSD, so the Shell item of
    # the console menu does not work with it. That is a separate defect we have
    # already fixed once. /usr/local/bin/zsh is the value of the official
    # TrueNAS CORE 13.3, verified on 13.3-U1.2. It is /usr/bin/zsh specifically
    # that is inadmissible: that is a Linux path, no such file exists on FreeBSD
    # and the Shell item of the console menu fails with it.
    case "$_shell" in
        /usr/local/bin/zsh|/bin/csh|/bin/sh|/bin/tcsh) ;;
        *) log "  NOTE: inadmissible root shell ($_shell)"; _rc=1 ;;
    esac

    return "$_rc"
}

# Checking that the configuration survives an upgrade: compare before and after.
verify_preserved() {
    local _before_pools="$1" _before_shares="$2"
    local _pools _shares
    _pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)

    if [ "${_pools:-0}" -lt "$_before_pools" ] || [ "${_shares:-0}" -lt "$_before_shares" ]; then
        fail "configuration lost: there were $_before_pools pools / $_before_shares shares, now there are ${_pools:-0} / ${_shares:-0}"
    fi
    log "configuration preserved: ${_pools} pools, ${_shares} shares"
}

case "${1:-}" in
install)
    [ $# -ge 2 ] || fail "an ISO name is required"
    boot_iso "$2"; run_installer fresh; boot_disk
    verify && log "ACCEPTANCE PASSED" || fail "the checks did not pass"
    ;;
upgrade)
    [ $# -ge 2 ] || fail "an ISO name is required"
    wait_ready 300 || fail "the original system does not answer"
    before_pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    before_shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    log "before the upgrade: ${before_pools} pools, ${before_shares} shares"
    boot_iso "$2"; run_installer upgrade; boot_disk
    verify || fail "the checks did not pass"
    verify_preserved "${before_pools:-0}" "${before_shares:-0}"
    log "UPGRADE ACCEPTANCE PASSED"
    ;;
verify)   verify && log "CHECKS PASSED" || fail "the checks did not pass" ;;
snapshot) [ $# -ge 2 ] || fail "a snapshot name is required"; snapshot "$2" ;;
rollback) [ $# -ge 2 ] || fail "a snapshot name is required"; rollback "$2" ;;
*)
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
