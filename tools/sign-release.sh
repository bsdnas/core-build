#!/usr/bin/env bash
#
# Подпись выпускаемого образа.
#
# Контрольная сумма без подписи защищает только от битой закачки: тот, кто
# способен подменить образ, подменит и файл с суммой. Подпись переносит доверие
# на ключ, который лежит не там, где образы.
#
# Использование:
#   tools/sign-release.sh <каталог с образом>        подписать
#   tools/sign-release.sh <каталог> --upload <тег>   подписать и приложить к релизу
#
# Ключ: BSDnas release signing <bsd@22r.tech>, ed25519, отпечаток
#   58528D1CDBDAAF7B01ED2BBE1E2F7A792066322D
#
# Секретная часть хранится офлайн; парольная фраза — в
# парольная фраза — в файле, путь к которому не документируется.
# Честно о границах: от полной компрометации этой машины такая схема не
# защищает — защищает от утечки одного лишь файла ключа (случайная копия
# в репозиторий, резервная копия, переданный архив). Следующий шаг, когда
# проект перестанет быть однопользовательским, — аппаратный токен.

set -eu

KEYID="${BSDNAS_SIGNKEY:-1E2F7A792066322D}"
PASSFILE="${BSDNAS_PASSFILE:-${BSDNAS_PASSFILE:?set BSDNAS_PASSFILE}}"
DIR="${1:-}"

[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "укажите каталог с образом" >&2; exit 1; }
[ -f "$PASSFILE" ] || { echo "не найдена парольная фраза: $PASSFILE" >&2; exit 1; }

cd "$DIR"

iso=$(ls -1 *.iso 2>/dev/null | head -1)
[ -n "$iso" ] || { echo "в каталоге нет .iso" >&2; exit 1; }

echo "==> считаю контрольную сумму: $iso"
sha256sum "$iso" > SHA256SUMS

echo "==> подписываю"
rm -f SHA256SUMS.asc
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --local-user "$KEYID" --armor --detach-sign SHA256SUMS

echo "==> экспортирую публичный ключ"
gpg --armor --export "$KEYID" > BSDnas-signing-key.asc

echo "==> проверяю подпись так же, как это сделает пользователь"
gpg --verify SHA256SUMS.asc SHA256SUMS

if [ "${2:-}" = "--upload" ]; then
    tag="${3:?укажите тег релиза}"
    echo "==> прикладываю к релизу $tag"
    gh release upload "$tag" "$iso" SHA256SUMS SHA256SUMS.asc BSDnas-signing-key.asc \
        --repo bsdnas/core-build --clobber
fi

echo "готово: $iso, SHA256SUMS, SHA256SUMS.asc, BSDnas-signing-key.asc"
