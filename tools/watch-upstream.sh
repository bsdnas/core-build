#!/usr/bin/env bash
#
# Наблюдатель за апстримом: показывает, что изменилось снаружи и требует нашей
# реакции. Ничего не меняет — только сообщает. Решение принимает человек
# (или агент, которому это доверят).
#
# Смысл в том, чтобы форк не гнил молча. Дерево портов, база FreeBSD, OpenZFS
# и бюллетени безопасности живут своей жизнью; пропущенный на полгода апстрим
# превращается в тот самый разрыв между CORE 13.3 и FreeBSD 15, который
# пришлось разгребать при старте проекта.
#
# Четыре наблюдения:
#   1. база FreeBSD   — сдвинулась ли stable/15 под нашим патч-сетом
#   2. безопасность   — свежие бюллетени FreeBSD SA/EN
#   3. дерево портов  — открыта ли следующая квартальная ветка
#   4. OpenZFS        — вышел ли релиз новее собранного
#
# Отчёт «всегда красный» перестают читать, поэтому наблюдатель ведёт журнал
# разобранного (.upstream-seen) и сообщает только про новое с прошлого раза.
#
# Использование:
#   tools/watch-upstream.sh              отчёт в терминал
#   tools/watch-upstream.sh --quiet      молчать, когда нового нет (для cron)
#   tools/watch-upstream.sh --ack        отметить текущее состояние разобранным
#
# Коды возврата: 0 — нового нет, 10 — есть о чём доложить, 1 — ошибка.

set -u

QUIET=0
ACK=0
case "${1:-}" in
--quiet) QUIET=1 ;;
--ack)   ACK=1 ;;
"")      ;;
*)       echo "неизвестный ключ: $1" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="$ROOT/build/profiles/freenas/repos.pyd"
SEEN="${SEEN_FILE:-$ROOT/.upstream-seen}"
[ -f "$REPOS" ] || { echo "не найден $REPOS" >&2; exit 1; }

FINDINGS=0
OUT=""
STATE=""            # состояние этого прогона, пишется в журнал при --ack

say()  { OUT="${OUT}$1
"; }
note() { FINDINGS=$((FINDINGS + 1)); say "$1"; }

# Запомнить наблюдаемое значение и ответить, новое ли оно
track() {
    STATE="${STATE}$1
"
    grep -qxF "$1" "$SEEN" 2>/dev/null && return 1
    return 0
}

# Значение branch для репозитория с данным name из repos.pyd
repo_branch() {
    python3 - "$REPOS" "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
name = sys.argv[2]
for block in text.split("repos +="):
    if f'"name": "{name}"' in block:
        m = re.search(r'"branch":\s*"([^"]+)"', block)
        if m:
            print(m.group(1))
            break
PY
}

# --- 1. База FreeBSD -------------------------------------------------------
watch_base() {
    local _branch _ours _theirs
    _branch=$(repo_branch os)
    _ours=$(git ls-remote https://github.com/bsdnas/os.git "refs/heads/${_branch}" 2>/dev/null | cut -f1)
    _theirs=$(git ls-remote https://github.com/freebsd/freebsd-src.git refs/heads/stable/15 2>/dev/null | cut -f1)

    if [ -z "$_ours" ] || [ -z "$_theirs" ]; then
        say "  не удалось опросить (сеть?)"
        return
    fi
    say "  наша ветка: ${_branch} @ ${_ours:0:9}"
    say "  upstream stable/15 @ ${_theirs:0:9}"

    # Точное отставание требует клона; здесь достаточно факта сдвига головы —
    # решение о переносе принимается уже с деревом на руках.
    if track "base:${_theirs}"; then
        note "  → stable/15 сдвинулась: перенести патч-сет"
        say  "    git rebase --onto up/stable/15 <прежняя-база> ${_branch}"
    fi
}

# --- 2. Бюллетени безопасности --------------------------------------------
watch_security() {
    local _feed _recent _new=""
    # advisories.rdf из старых инструкций отдаёт 404; рабочий адрес — feed.xml.
    # Лента содержит и SA (безопасность), и EN (errata).
    _feed=$(curl -s --max-time 25 https://www.freebsd.org/security/feed.xml 2>/dev/null)
    if [ -z "$_feed" ]; then
        say "  лента недоступна"
        return
    fi
    _recent=$(printf '%s' "$_feed" |
        grep -oE 'FreeBSD-(SA|EN)-[0-9]{2}:[0-9]+\.[a-zA-Z0-9_]+' | awk '!seen[$0]++' | head -6)
    if [ -z "$_recent" ]; then
        say "  разобрать ленту не удалось (изменился формат?)"
        return
    fi

    say "  последние:"
    while read -r a; do
        [ -n "$a" ] || continue
        say "    $a"
        track "adv:${a}" && _new="${_new}${a} "
    done <<EOF
$_recent
EOF

    if [ -n "$_new" ]; then
        note "  → новые с прошлой проверки: ${_new% }"
        say  "    сверить со stable/15 и отметить: tools/watch-upstream.sh --ack"
    fi
}

# --- 3. Дерево портов ------------------------------------------------------
watch_ports() {
    local _cur _year _q _next
    _cur=$(repo_branch ports)
    say "  наша ветка: ${_cur}"

    _year=${_cur%Q*}; _q=${_cur#*Q}
    if [ "$_q" -ge 4 ]; then _next="$((_year + 1))Q1"; else _next="${_year}Q$((_q + 1))"; fi

    if git ls-remote --exit-code --heads \
        https://github.com/freebsd/freebsd-ports.git "$_next" >/dev/null 2>&1; then
        if track "ports:${_next}"; then
            note "  → открыта следующая квартальная: ${_next}"
            say  "    менять ветку в repos.pyd только вместе с полной пересборкой"
        else
            say "  следующая (${_next}) открыта, переход отложен осознанно"
        fi
    else
        say "  следующая (${_next}) ещё не открыта"
    fi
}

# --- 4. OpenZFS ------------------------------------------------------------
watch_openzfs() {
    local _mk _ours _tag _latest
    _mk=$(curl -s --max-time 25 \
        https://raw.githubusercontent.com/bsdnas/middleware/bsdnas/nas_ports/filesystems/openzfs/Makefile 2>/dev/null)
    _ours=$(printf '%s' "$_mk" | sed -n 's/^PORTVERSION=[[:space:]]*//p' | head -1)
    _tag=$(curl -s --max-time 25 https://api.github.com/repos/openzfs/zfs/releases/latest 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null)
    # Релизы OpenZFS помечены как zfs-2.4.3 — версия порта это тот же тег
    # без префикса. Сравнивать надо очищенные значения, иначе наблюдатель
    # вечно требует обновления на уже собранную версию.
    _latest=${_tag#zfs-}
    _latest=${_latest#v}

    if [ -z "$_ours" ] || [ -z "$_latest" ]; then
        say "  сравнить версии не удалось"
        return
    fi
    say "  у нас ${_ours}, последний релиз ${_latest}"
    if [ "$_ours" != "$_latest" ] && track "openzfs:${_latest}"; then
        note "  → доступно обновление до ${_latest}"
        say  "    middleware: tools/update_openzfs_ports.py ${_latest} <sha тега>"
    fi
}

say "Наблюдение за апстримом — $(date '+%Y-%m-%d %H:%M')"
say ""
say "База FreeBSD:";  watch_base
say ""
say "Безопасность:";  watch_security
say ""
say "Дерево портов:"; watch_ports
say ""
say "OpenZFS:";       watch_openzfs
say ""

if [ "$ACK" -eq 1 ]; then
    printf '%s' "$STATE" > "$SEEN"
    printf '%s' "$OUT"
    echo "состояние отмечено разобранным: $SEEN"
    exit 0
fi

say "Требуют внимания: ${FINDINGS}"
if [ "$QUIET" -eq 1 ] && [ "$FINDINGS" -eq 0 ]; then
    exit 0
fi
printf '%s' "$OUT"
[ "$FINDINGS" -gt 0 ] && exit 10
exit 0
