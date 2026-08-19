#!/bin/sh
#
# Уборка артефактов прошлых сборок на сборочной машине.
#
# Каждый прогон `make release` оставляет в _BE/release каталог примерно на
# 1.3 ГБ и ISO рядом с ним. Ничто их не удаляет. За неделю отладки набежало
# 29 каталогов и 44 ГБ, корневой раздел кончился — и сборка упала через
# 4 часа 50 минут на rust, grub2-efi и сборке Angular, причём каждое падение
# выглядело как отдельная поломка. Настоящая причина была одна: ENOSPC.
#
# Поэтому уборка — часть регламента, а не разовое действие.
#
# Использование:
#   tools/prune-builds.sh            показать, что будет удалено
#   tools/prune-builds.sh --apply    удалить
#   KEEP=5 tools/prune-builds.sh     сколько последних сборок оставить (по умолчанию 3)

set -u

KEEP="${KEEP:-3}"
BE="${BE:-/usr/build/freenas/_BE}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

[ -d "$BE/release" ] || { echo "не найден $BE/release" >&2; exit 1; }
cd "$BE/release" || exit 1

# Сортируем по фактическому времени, а не по метке в имени каталога.
# Считаем ТОЛЬКО каталоги сборок BSDnas-15-MASTER-*: 2026-08-19 скрипт
# посчитал «последними» служебные каталоги (Nightlies-Update) и удалил
# каталог свежей сборки вместе с ISO.
total=$(ls -1dt BSDnas-15-MASTER-*/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$total" -le "$KEEP" ]; then
    echo "сборок: ${total}, оставляем ${KEEP} — удалять нечего"
    exit 0
fi

doomed=$(ls -1dt BSDnas-15-MASTER-*/ 2>/dev/null | sed 's,/$,,' | tail -n +$((KEEP + 1)))
freed=$(echo "$doomed" | while read -r d; do
    [ -n "$d" ] && du -sk "$d" 2>/dev/null | cut -f1
done | awk '{s += $1} END {printf "%d", s / 1048576}')

printf 'сборок: %s, оставляем %s, удаляем %s (примерно %s ГБ)\n' \
    "$total" "$KEEP" "$(echo "$doomed" | wc -l | tr -d ' ')" "$freed"

echo "$doomed" | while read -r d; do
    [ -n "$d" ] || continue
    if [ "$APPLY" -eq 1 ]; then
        rm -rf "$d" && echo "  удалено: $d"
    else
        echo "  будет удалено: $d"
    fi
done

if [ "$APPLY" -eq 1 ]; then
    # образы лежат рядом с объектным каталогом и живут своей жизнью
    ls -1t "$BE"/objs/*.iso 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r iso; do
        rm -f "$iso" && echo "  удалён образ: $(basename "$iso")"
    done
    echo "свободно на разделе: $(df -h "$BE" | tail -1 | awk '{print $4}')"
else
    echo "запустите с --apply, чтобы удалить"
fi
