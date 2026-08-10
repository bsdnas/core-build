#!/usr/bin/env bash
#
# Автоприёмка образа bsdnas: поставить систему из ISO и проверить, что она
# действительно работает — а не только собралась.
#
# Ручной цикл, который этот скрипт заменяет, за время отладки был пройден
# полтора десятка раз и каждый раз занимал около часа внимания. Все приёмы
# здесь уже отлажены вживую: ввод в установщик через QEMU sendkey, снятие
# экрана через screendump, проверки через REST API.
#
# Использование:
#   acceptance.sh install <iso>            чистая установка и проверка
#   acceptance.sh upgrade <iso>            обновление поверх текущей системы
#   acceptance.sh verify                   только проверки, без установки
#   acceptance.sh snapshot <имя>           снять точку возврата
#   acceptance.sh rollback <имя>           вернуть стенд в точку возврата
#
# Переменные окружения (значения по умолчанию — наш стенд):
#   PVE      ssh-адрес гипервизора            root@proxmox.example
#   VMID     тестовая VM                      147
#   NASIP    адрес поднятой системы           nas.example
#   NASPW    пароль root                      СКРЫТО
#   STORAGE  хранилище с ISO                  nfs-kmdz

set -u

PVE="${PVE:-root@proxmox.example}"
VMID="${VMID:-147}"
NASIP="${NASIP:-nas.example}"
NASPW="${NASPW:-СКРЫТО}"
STORAGE="${STORAGE:-nfs-kmdz}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"

log()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '%s  ОТКАЗ: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

pve()      { timeout 120 $SSH "$PVE" "$@"; }
key()      { pve "printf 'sendkey $1\n' | qm monitor $VMID >/dev/null 2>&1"; }
# Печать строки без Enter — пароли и поля ввода
text()     { pve "bash /tmp/sendtext.sh $VMID '$1'"; }
api()      { pve "timeout 30 curl -sk -u root:$NASPW https://$NASIP/api/v2.0/$1" 2>/dev/null; }

# Ждём, пока middleware не ответит READY. Дольше, чем кажется нужным:
# после обновления идут миграции базы.
wait_ready() {
    local _t=0
    while [ "$_t" -lt "${1:-600}" ]; do
        if [ "$(api system/state)" = '"READY"' ]; then
            log "система готова (${_t}с)"
            return 0
        fi
        sleep 20; _t=$((_t + 20))
    done
    return 1
}

snapshot() { pve "qm snapshot $VMID $1 --description 'автоприёмка'" >/dev/null 2>&1 && log "снимок $1 снят"; }

# Запись последовательной консоли на гипервизоре. Без неё отказ установки
# выглядит как "система не поднялась": настоящая причина остаётся на экране,
# который автоматика не читает. В образе установщика включён вывод и на
# vidconsole, и на comconsole (templates/cdrom/loader.conf).
CONSOLE_LOG="/tmp/acceptance-${VMID}.console"

console_start() {
    # Одной строкой и без переносов: многострочная команда через ssh
    # разбиралась удалённой оболочкой не так, как ожидалось, и запись
    # молча не начиналась.
    pve "rm -f ${CONSOLE_LOG}; setsid socat -u UNIX-CONNECT:/var/run/qemu-server/${VMID}.serial0 CREATE:${CONSOLE_LOG} >/dev/null 2>&1 < /dev/null & sleep 1; test -e ${CONSOLE_LOG} && echo ok" >/dev/null 2>&1
    if [ "$(pve "test -e ${CONSOLE_LOG} && echo ok")" != "ok" ]; then
        log "ВНИМАНИЕ: запись консоли не началась — диагностика будет беднее"
    fi
}

console_stop() { pve "pkill -f 'UNIX-CONNECT:/var/run/qemu-server/${VMID}.serial0'" >/dev/null 2>&1; }

# Ищем в консоли признаки того, что установка не состоялась. Проверяется
# именно текст установщика, а не косвенные симптомы.
console_check_install() {
    local _out
    _out=$(pve "grep -aiE 'installation on .* has failed|Traceback \(most recent|FileNotFoundError|No space left on device|cannot open|Abort' ${CONSOLE_LOG} 2>/dev/null | head -5")
    [ -n "$_out" ] || return 0
    printf '%s\n' "$_out" | sed 's/^/    /' >&2
    return 1
}

# Снимок экрана — последняя линия обороны, когда в консоли пусто
screenshot() {
    local _name="${1:-fail}"
    pve "printf 'screendump /tmp/${_name}.ppm\n' | qm monitor $VMID >/dev/null 2>&1; \
         sleep 2; pnmtopng /tmp/${_name}.ppm > /tmp/${_name}.png 2>/dev/null" >/dev/null 2>&1
    log "снимок экрана: ${PVE}:/tmp/${_name}.png"
}

rollback() {
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6; qm rollback $VMID $1" >/dev/null 2>&1 || fail "откат на $1 не удался"
    pve "qm set $VMID --boot order=scsi0 >/dev/null 2>&1; qm start $VMID" >/dev/null 2>&1
    log "стенд возвращён в точку $1"
}

boot_iso() {
    local _iso="$1"
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    # порядок загрузки задаём ОТДЕЛЬНОЙ командой: Proxmox пересобирает его при
    # подключении носителя в той же команде и ставит диск первым
    pve "qm set $VMID --ide2 $STORAGE:iso/$_iso,media=cdrom" >/dev/null 2>&1
    pve "qm set $VMID --boot order=ide2" >/dev/null 2>&1
    pve "qm start $VMID" >/dev/null 2>&1
    console_start
    log "загрузка с $_iso (консоль пишется в ${CONSOLE_LOG})"
    sleep 200
}

boot_disk() {
    pve "qm stop $VMID >/dev/null 2>&1; sleep 6"
    pve "qm set $VMID --ide2 none,media=cdrom" >/dev/null 2>&1
    pve "qm set $VMID --boot order=scsi0" >/dev/null 2>&1
    pve "qm start $VMID" >/dev/null 2>&1
    log "загрузка с диска"
}

# Затереть начало и конец загрузочного диска, чтобы установщик видел его
# пустым. Без этого набор диалогов зависит от того, что осталось на диске от
# прошлых попыток, и слепая последовательность клавиш перестаёт совпадать
# с экранами.
wipe_boot_disk() {
    local _zvol="/dev/zvol/local-zfs/vm-${VMID}-disk-0"
    pve "test -e ${_zvol} || exit 1; \
         dd if=/dev/zero of=${_zvol} bs=1M count=64 conv=notrunc 2>/dev/null; \
         sz=\$(blockdev --getsz ${_zvol}); \
         dd if=/dev/zero of=${_zvol} bs=512 seek=\$((sz-2048)) count=2048 conv=notrunc 2>/dev/null" >/dev/null 2>&1 \
        && log "загрузочный диск очищен" \
        || log "ВНИМАНИЕ: очистить загрузочный диск не удалось"
}

# Прохождение установщика. mode: fresh | upgrade
#
# Последовательность клавиш слепая — установщик рисует диалоги только на
# видеоконсоли, прочитать их нечем. Поэтому важно, чтобы состояние диска было
# известно заранее: набор экранов от него зависит.
#
# fresh (диск пуст):
#   Install/Upgrade -> выбор диска -> предупреждение (Yes) -> пароль ->
#   режим загрузки (BIOS) -> установка -> OK
# upgrade (на диске рабочая установка):
#   Install/Upgrade -> выбор диска -> Upgrade Install ->
#   новая загрузочная среда -> установка -> OK
#
# ГРАБЛИ: на пустом диске диалогов "Fresh Install / Upgrade" и "Format the
# boot device" НЕТ. Прежняя версия жала в них right+ret, попадая на кнопку
# "No" в предупреждении, и установка молча отменялась — а приёмка через
# 15 минут сообщала "система не пришла в состояние READY".
run_installer() {
    local _mode="$1"
    key ret;  sleep 12          # Install/Upgrade
    key spc;  sleep 3
    key ret;  sleep 16          # выбран диск da0
    if [ "$_mode" = upgrade ]; then
        key ret; sleep 16       # Upgrade Install
        key ret; sleep 18       # Install in new boot environment
        key ret; sleep 500      # подтверждение + установка
    else
        key ret;  sleep 14                      # Yes: стереть диск
        text "$NASPW"; sleep 3                  # пароль
        key tab;  sleep 3
        text "$NASPW"; sleep 3
        key ret;  sleep 14
        key ret;  sleep 420                     # Boot via BIOS + установка
    fi
    key ret; sleep 8            # OK на итоговом окне

    # Сразу после установщика, до перезагрузки: не упала ли установка.
    # Раньше отказ обнаруживался только через 15 минут ожидания READY.
    if ! console_check_install; then
        screenshot "install-failed"
        fail "установка не выполнена — см. вывод выше и снимок экрана"
    fi
}

# Проверки живой системы. Именно то, что отличает "собралось" от "работает".
verify() {
    local _rc=0 _v _pools _shares _shell

    if ! wait_ready 900; then
        console_check_install || true
        screenshot "not-ready"
        fail "система не пришла в состояние READY"
    fi

    _v=$(api system/version)
    log "версия: $_v"

    _pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shell=$(api user | python3 -c '
import json,sys
for u in json.load(sys.stdin):
    if u.get("username") == "root":
        print(u.get("shell"))' 2>/dev/null)

    log "пулов: ${_pools:-?}, шар: ${_shares:-?}, шелл root: ${_shell:-?}"

    # Шелл /usr/bin/zsh во FreeBSD не существует — пункт Shell консольного
    # меню с ним не работает. Это отдельный дефект, который мы уже чинили.
    # /usr/local/bin/zsh — значение официальной TrueNAS CORE 13.3, проверено
    # на 13.3-U1.2. Недопустим именно /usr/bin/zsh: это линуксовый путь,
    # во FreeBSD такого файла нет и пункт Shell консольного меню с ним падает.
    case "$_shell" in
        /usr/local/bin/zsh|/bin/csh|/bin/sh|/bin/tcsh) ;;
        *) log "  ЗАМЕЧАНИЕ: недопустимый шелл root ($_shell)"; _rc=1 ;;
    esac

    return "$_rc"
}

# Проверка сохранности конфигурации при обновлении: сверяем до и после.
verify_preserved() {
    local _before_pools="$1" _before_shares="$2"
    local _pools _shares
    _pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    _shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)

    if [ "${_pools:-0}" -lt "$_before_pools" ] || [ "${_shares:-0}" -lt "$_before_shares" ]; then
        fail "конфигурация потеряна: было пулов $_before_pools / шар $_before_shares, стало ${_pools:-0} / ${_shares:-0}"
    fi
    log "конфигурация сохранена: пулов ${_pools}, шар ${_shares}"
}

case "${1:-}" in
install)
    [ $# -ge 2 ] || fail "нужно имя ISO"
    wipe_boot_disk
    boot_iso "$2"; run_installer fresh; boot_disk
    verify && log "ПРИЁМКА ПРОЙДЕНА" || fail "проверки не прошли"
    ;;
upgrade)
    [ $# -ge 2 ] || fail "нужно имя ISO"
    wait_ready 300 || fail "исходная система не отвечает"
    before_pools=$(api pool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    before_shares=$(api sharing/smb | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)
    log "до обновления: пулов ${before_pools}, шар ${before_shares}"
    boot_iso "$2"; run_installer upgrade; boot_disk
    verify || fail "проверки не прошли"
    verify_preserved "${before_pools:-0}" "${before_shares:-0}"
    log "ПРИЁМКА ОБНОВЛЕНИЯ ПРОЙДЕНА"
    ;;
verify)   verify && log "ПРОВЕРКИ ПРОЙДЕНЫ" || fail "проверки не прошли" ;;
snapshot) [ $# -ge 2 ] || fail "нужно имя снимка"; snapshot "$2" ;;
rollback) [ $# -ge 2 ] || fail "нужно имя снимка"; rollback "$2" ;;
*)
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
