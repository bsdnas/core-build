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
# The bench is set by environment variables, no addresses of our own are here:
#   PVE      ssh address of the Proxmox host   root@proxmox.example
#   VMID     number of the test VM             147
#   NASIP    address of the running system     nas.example
#   NASPW    root password of the test system  (must be set)
#   STORAGE  Proxmox storage holding images    local
#
# Example:
#   PVE=root@10.0.0.5 VMID=200 NASIP=10.0.0.50 NASPW=secret \
#     tools/acceptance.sh install BSDnas-15-MASTER-....iso

set -u

PVE="${PVE:?specify the ssh address of the hypervisor, for example root@proxmox.example}"
VMID="${VMID:-147}"
NASIP="${NASIP:?specify the address of the test system}"
NASPW="${NASPW:?specify the root password of the test system}"
STORAGE="${STORAGE:-local}"
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

# Serial console capture on the hypervisor. Without it a failed installation
# looks like "the system did not come up": the real cause stays on the screen,
# which the automation does not read. The installer image has output enabled on
# both vidconsole and comconsole (templates/cdrom/loader.conf).
CONSOLE_LOG="/tmp/acceptance-${VMID}.console"

console_start() {
    # One line and no continuations: a multi-line command sent over ssh was
    # parsed by the remote shell differently than expected, and the capture
    # silently did not start.
    pve "rm -f ${CONSOLE_LOG}; setsid socat -u UNIX-CONNECT:/var/run/qemu-server/${VMID}.serial0 CREATE:${CONSOLE_LOG} >/dev/null 2>&1 < /dev/null & sleep 1; test -e ${CONSOLE_LOG} && echo ok" >/dev/null 2>&1
    if [ "$(pve "test -e ${CONSOLE_LOG} && echo ok")" != "ok" ]; then
        log "WARNING: console capture did not start, diagnostics will be poorer"
    fi
}

console_stop() { pve "pkill -f 'UNIX-CONNECT:/var/run/qemu-server/${VMID}.serial0'" >/dev/null 2>&1; }

# Look in the console for signs that the installation did not happen. What is
# checked is the installer's own text, not indirect symptoms.
console_check_install() {
    local _out
    _out=$(pve "grep -aiE 'installation on .* has failed|Traceback \(most recent|FileNotFoundError|No space left on device|cannot open|Abort' ${CONSOLE_LOG} 2>/dev/null | head -5")
    [ -n "$_out" ] || return 0
    printf '%s\n' "$_out" | sed 's/^/    /' >&2
    return 1
}

# A screenshot is the last line of defence when the console log is empty
screenshot() {
    local _name="${1:-fail}"
    pve "printf 'screendump /tmp/${_name}.ppm\n' | qm monitor $VMID >/dev/null 2>&1; \
         sleep 2; pnmtopng /tmp/${_name}.ppm > /tmp/${_name}.png 2>/dev/null" >/dev/null 2>&1
    log "screenshot: ${PVE}:/tmp/${_name}.png"
}

rollback() {
    local _err
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    _err=$(pve "qm rollback $VMID $1 2>&1" | grep -viE "^perl:|locale|are supported" | tail -2)

    # ZFS cannot roll back over an intermediate snapshot: if there are newer
    # snapshots after the wanted one, a rollback is impossible until they are
    # deleted. The previous version merely reported "rollback failed" and left
    # the reason to be worked out by hand.
    case "$_err" in
    *"not most recent snapshot"*)
        printf '%s\n' "$_err" | sed 's/^/    /' >&2
        log "  hint: delete the newer snapshots, qm listsnapshot $VMID, then qm delsnapshot $VMID <name>"
        fail "rollback to $1 is impossible: newer snapshots exist"
        ;;
    esac
    [ -n "$_err" ] && printf '%s\n' "$_err" | sed 's/^/    /' >&2

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
    console_start
    log "booting from $_iso (the console is captured into ${CONSOLE_LOG})"
    sleep 200
}

boot_disk() {
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    pve "qm set $VMID --ide2 none,media=cdrom" >/dev/null 2>&1
    pve "qm set $VMID --boot order=scsi0" >/dev/null 2>&1
    pve "qm start $VMID" >/dev/null 2>&1
    log "booting from the disk"
}

# Wipe the beginning and the end of the boot disk so that the installer sees it
# as empty. Without that the set of dialogs depends on what previous attempts
# left on the disk, and the blind key sequence stops matching the screens.
wipe_boot_disk() {
    local _ds _zvol _sz
    # The device path is searched for rather than guessed: a zvol can sit at
    # an arbitrary nesting depth (say rpool/data/vm-100-disk-0), and the
    # /dev/zvol/*/... pattern does not cover it.
    _ds=$(pve "zfs list -H -o name -t volume 2>/dev/null | grep -m1 'vm-${VMID}-disk-0\$'")
    if [ -z "$_ds" ]; then
        log "WARNING: the boot disk was not found among the zvols, the wipe is skipped"
        return 0
    fi
    _zvol="/dev/zvol/${_ds}"

    _sz=$(pve "blockdev --getsz ${_zvol} 2>/dev/null")
    if [ -z "$_sz" ]; then
        log "WARNING: ${_zvol} is not available, the wipe is skipped"
        return 0
    fi

    # The beginning (partition table and boot code) and the end (backup GPT)
    pve "dd if=/dev/zero of=${_zvol} bs=1M count=64 conv=notrunc 2>/dev/null; \
         dd if=/dev/zero of=${_zvol} bs=512 seek=\$((${_sz}-2048)) count=2048 conv=notrunc 2>/dev/null" >/dev/null 2>&1
    log "boot disk wiped (${_ds})"
}

# Walking through the installer. mode: fresh | upgrade
#
# The key sequence is blind: the installer draws its dialogs on the video
# console only, and there is nothing to read them with. That is why the state of
# the disk has to be known in advance: the set of screens depends on it.
#
# fresh (the disk is empty):
#   Install/Upgrade -> disk selection -> warning (Yes) -> password ->
#   boot mode (BIOS) -> installation -> OK
# upgrade (a working installation on the disk):
#   Install/Upgrade -> disk selection -> Upgrade Install ->
#   new boot environment -> installation -> OK
#
# PITFALL: on an empty disk the "Fresh Install / Upgrade" and "Format the boot
# device" dialogs are NOT shown. The previous version pressed right+ret in them,
# landing on the "No" button of the warning, so the installation was silently
# cancelled, and acceptance reported "the system did not reach the READY state"
# 15 minutes later.
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
        key ret;  sleep 14                      # Yes: erase the disk
        text "$NASPW"; sleep 3                  # password
        key tab;  sleep 3
        text "$NASPW"; sleep 3
        key ret;  sleep 14
        key ret;  sleep 420                     # Boot via BIOS + installation
    fi
    key ret; sleep 8            # OK on the final window

    # Right after the installer and before the reboot: did the installation
    # fail. Previously a failure was only discovered after 15 minutes of
    # waiting for READY.
    if ! console_check_install; then
        screenshot "install-failed"
        fail "installation did not complete, see the output above and the screenshot"
    fi
}

# Checks on the live system. Exactly what tells "it built" from "it works".
verify() {
    local _rc=0 _v _pools _shares _shell

    if ! wait_ready 900; then
        console_check_install || true
        screenshot "not-ready"
        fail "the system did not reach the READY state"
    fi

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
    wipe_boot_disk
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
