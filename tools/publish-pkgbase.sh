#!/bin/sh
#
# Publish the base package repository built by `make packages`.
#
# The build leaves the repository under OBJDIR/pkgbase-repo, one directory per
# build plus a `latest` symlink. This copies the current one to the update
# server, where installed systems fetch it from to update their base with pkg
# instead of unpacking a whole image.
#
# The server is given on the command line: nothing about the project's
# infrastructure belongs in this repository.
#
# Usage:
#   publish-pkgbase.sh <user@host> [remote-path] [repo-dir]
#
#   user@host     where to publish, over ssh
#   remote-path   directory served as /pkgbase/  (default /var/www/updates/pkgbase)
#   repo-dir      local repository              (default from the build tree)
#
# Example:
#   tools/publish-pkgbase.sh deploy@updates.example.com
#
# What it does, in order:
#   * refuses to publish a repository without a catalogue — a half-copied
#     repository is worse than none, because clients see it and fail;
#   * copies packages first and the catalogue last, so a client that fetches
#     mid-copy never sees a catalogue referring to packages that are not there
#     yet;
#   * keeps the previous build on the server until the new one is complete.

set -eu

usage() {
    sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

[ $# -ge 1 ] || usage

TARGET="$1"
REMOTE="${2:-/var/www/updates/pkgbase}"
REPO="${3:-}"

if [ -z "${REPO}" ]; then
    # Ищем репозиторий в дереве сборки: build/… → freenas/_BE/objs
    _root=$(cd "$(dirname "$0")/.." && pwd)
    REPO="${_root}/freenas/_BE/objs/pkgbase-repo"
fi

[ -d "${REPO}" ] || { echo "нет репозитория: ${REPO}" >&2; exit 1; }

# Внутри репозитория каталог называется по ABI (FreeBSD:15:amd64), а в нём —
# сборки со ссылкой latest на текущую.
ABI_DIR=$(find "${REPO}" -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "${ABI_DIR}" ] || { echo "в ${REPO} нет каталога ABI" >&2; exit 1; }
ABI=$(basename "${ABI_DIR}")

LATEST="${ABI_DIR}/latest"
[ -e "${LATEST}" ] || { echo "нет ${LATEST} — сборка pkgbase не завершилась" >&2; exit 1; }

BUILD=$(readlink "${LATEST}" || basename "${LATEST}")
SRC="${ABI_DIR}/${BUILD}"

# Каталог — то, по чему клиент понимает, что в репозитории есть. Без него
# публиковать нечего.
for f in meta.conf packagesite.pkg; do
    [ -f "${SRC}/${f}" ] || { echo "в сборке нет ${f} — репозиторий неполон" >&2; exit 1; }
done

COUNT=$(find "${SRC}" -name '*.pkg' | wc -l | tr -d ' ')
SIZE=$(du -sh "${SRC}" | awk '{print $1}')
echo "публикую ${ABI}/${BUILD}: ${COUNT} пакетов, ${SIZE} -> ${TARGET}:${REMOTE}"

ssh "${TARGET}" "mkdir -p '${REMOTE}/${ABI}'"

# Сначала пакеты, потом каталог: клиент, зашедший в середине копирования,
# увидит старый каталог и старые пакеты — согласованную картину.
rsync -a --info=progress2 \
    --exclude 'meta.conf' --exclude 'meta.txz' \
    --exclude 'packagesite.*' --exclude 'data.*' \
    "${SRC}/" "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

rsync -a \
    --include 'meta.*' --include 'packagesite.*' --include 'data.*' \
    --exclude '*' \
    "${SRC}/" "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

# Переключаем latest после того, как всё на месте.
ssh "${TARGET}" "cd '${REMOTE}/${ABI}' && ln -sfn '${BUILD}' latest.new && mv -Tf latest.new latest"

echo "опубликовано: ${REMOTE}/${ABI}/${BUILD}, latest переключён"
echo
echo "на клиенте:"
echo "  /usr/local/etc/pkg/repos/bsdnas-base.conf"
echo "  bsdnas-base: { url: \"https://<сервер>/pkgbase/${ABI}/latest\", enabled: yes }"
