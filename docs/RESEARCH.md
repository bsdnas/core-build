# TrueNAS CORE (FreeBSD): исходники, состояние проекта и путь на свежий FreeBSD

Дата исследования: 2026-08-02.

## 1. Что склонировано в этот проект

```
truenas-core/          официальные исходники iXsystems (последняя версия CORE)
  core-build/          https://github.com/truenas/core-build  (бывш. truenas/build) — система сборки
  middleware/          https://github.com/truenas/middleware, ветка truenas/13.3-u1-stable
                       (бывш. truenas/freenas: middleware + nas_ports + src)
  os/                  https://github.com/truenas/os, ветка truenas/13.3-stable — форк FreeBSD
                       (+ remote `upstream` = github.com/freebsd/freebsd-src)
  webui/               https://github.com/truenas/webui, ветка truenas/13.3-stable
  freenas-pkgtools/    механизм обновлений (freenas-update, манифесты, трейны)

forks/                 живой community-форк, доведённый до FreeBSD 15
  dravanet-core-build/ ветка master-dravanet
  dravanet-middleware/ ветка truenas/13.3-stable-dravanet
  dravanet-os/         ветка freebsd/releng/15.0-dravanet (+ remote `up` = freebsd-src)

zvault/
  zvio-build/          система сборки форка zVault (заморожен с мая 2025)
```

Авторизация на GitHub нигде не требуется — все репозитории публичные.

## 2. Состояние официального CORE

* Последний релиз — **TrueNAS CORE 13.3-U1.2, 29 апреля 2025**, база **FreeBSD 13.3-RELEASE-p2**.
  В документации iX прямо написано: «13.3-U1.2 was the final release for the TrueNAS CORE 13.3
  software train».
* Ветка 13.0 закончилась на 13.0-U6.8 (теги `TN-13.0-U6.3…U6.8` указывают на один и тот же коммит
  middleware — это были только пере-сборки).
* Последние коммиты в `truenas/middleware` (ветка `truenas/13.3-u1-stable`) — **ноябрь 2024**,
  в `core-build` (master) — **18.11.2024**. Разработка не возобновлялась.
* Официальный путь миграции по версии iX — TrueNAS 25.10 (Goldeye), Linux.
* **FreeBSD 13 снят с поддержки.** Актуальны stable/15 (EOL 31.12.2029), releng/15.1 (до 31.03.2027),
  releng/15.0 (до 30.09.2026), stable/14 (до 30.11.2028), releng/14.4 (до 31.12.2026).
  То есть штатный CORE сегодня работает на базе, не получающей security-патчей.

## 3. Как устроена сборка CORE

Точка входа — `core-build` (FreeBSD-make + Python-DSL). Манифест репозиториев —
`build/profiles/freenas/repos.pyd`; в официальном 13.3 он тянет:

| repo | branch |
|---|---|
| os (форк FreeBSD) | truenas/13.3-stable |
| freenas (middleware) | truenas/13.3-stable |
| webui | truenas/13.3-stable |
| ports (форк дерева портов) | truenas/13.3-stable |
| py-licenselib, freenas-pkgtools, py-bsd | master |
| iocage | truenas/13.0-stable |

Цели: `make checkout` → `make update` → `make release` (внутри: `os`, `ports`, `packages`,
`freenas`, `cdrom`/`images`, `update`). Сборочная машина — FreeBSD 13.x, ~16 ГБ RAM, ~80 ГБ диска.
Артефакты: ISO и upgrade-tar (`build/tools/create-upgrade-distribution.py`,
`build/tools/create-iso.py`). Шага подписи в репозитории сборки нет — подпись/публикация трейна
делались отдельно на `update-master.tn.ixsystems.net` (цели `update-push`, `release-push`).
Слой TrueNAS-специфичных портов (`freenas/*`: freenas-files, freenas-migrate93, middlewared,
openzfs, webui и т. д.) живёт в `middleware/nas_ports/` и накладывается поверх дерева портов.

## 4. Кто продолжает FreeBSD-линию

### 4.1 dravanet (Richard Kojedzinszky) — **самый живой вариант, уже на FreeBSD 15.0**

Набор форков `dravanet/truenas-*`, активность до **20 июля 2026**. В `repos.pyd` его сборки:

| repo | branch |
|---|---|
| os | `dravanet/truenas-os` → `freebsd/releng/15.0-dravanet` |
| freenas | `dravanet/truenas-middleware` → `truenas/13.3-stable-dravanet` |
| webui | `dravanet/truenas-webui` → `truenas/13.3-stable` |
| **ports** | **`freebsd/freebsd-ports` → `2026Q2`** (форк дерева портов выброшен) |
| py-bsd | `dravanet/py-bsd` → master |
| iocage | `freenas/iocage` → truenas/13.0-u6.3-stable |

Ключевые вехи по коммитам:
`Build TrueNAS 13.3 based on FreeBSD releng/14.3` (09.07.2025) → `feat: freebsd 15 compatibility`
и `feat: build from FreeBSD 15.0` (05.04.2026) → `feat: update ports tree to 2026Q2` (12.04.2026).
Плюс: OpenZFS обновлён до **2.4.3**, Samba — на upstream **net/samba423**, py-libzfs подтянут
к 25.04, http2 в nginx, снят лимит на число дисков boot-pool.

Готовых ISO/релизов он не публикует — это исходники и система сборки, собирать надо самому.

### 4.2 zVault — фактически заморожен

Форк CORE 13.3 с вычищенным брендингом iX (первый релиз 25.02.2025 сняли по претензии iXsystems
об авторских правах, затем перевыпустили). Репозитории `zvaultio/zvio-*`: последние пуши —
**май 2025**, последний релиз — `zVault-13.3-MASTER-202505042329` (04.05.2025, prerelease).
В трекере висит открытый с 17.05.2025 вопрос о планах перехода на FreeBSD 14/15 — без ответа
мейнтейнеров. По роадмапу переход на FreeBSD 14 стоял только 4-м шагом. Признаков жизни за 2026 год нет.

### 4.3 xiphis — частный ребейз на FreeBSD 13.5

`xiphis/freenas-os` ветка `releng/13.5`, полный набор форков, активность до **ноября 2025**.
Промежуточный вариант: остаётся в пределах 13.x (тоже EOL), но новее, чем 13.3.

### 4.4 JohnM549/OpenNAS, os-14.3

Ветки `codex/update-to-freebsd-14.3` — попытка автоматического (Codex) переноса, декабрь 2025.
Отдельного сообщества/релизов нет, качество не проверялось.

### 4.5 XigmaNAS — не форк CORE, но живая FreeBSD-NAS

Другая кодовая линия (NAS4Free/FreeNAS 7), но активно развивается: стабильный релиз
14.3.0.5.10432 от 10.09.2025 на базе FreeBSD 14.3-RELEASE-P4. Если нужен именно поддерживаемый
FreeBSD-NAS, а не именно TrueNAS-middleware, это самая надёжная опция «из коробки».

## 5. Насколько тяжело перевести CORE на свежий FreeBSD — измерено по репозиториям

**База (os).** Разница `truenas/13.3-stable` относительно точки расхождения с upstream stable/13:
129 коммитов, 424 файла. Но подавляющая часть — это не iX-специфика, а вендорные подтягивания
(contrib/sendmail — 116 файлов, contrib/expat — 74, unbound, tzdata, caroot) и cherry-pick
апстримных фиксов. Реально своё у iX:

* `usr.sbin/ixnvdimm` + драйвер NVDIMM (нужен только их HA-железу);
* доработки CTL/isp (в основном уже в апстриме — автор Alexander Motin коммитит и в FreeBSD);
* bhyve/vncserver (сокращённые тайм-ауты RFB), EFI-serial console в загрузчике;
* `utimensat(2)` с явным birthtime, sysctl для generation, `pmbr-datadisk`, мелочи в rc-скриптах.

Насколько это мало — видно по dravanet: поверх `releng/15.0` у него всего **7 коммитов, 12 файлов**
(живая перенастройка ctld, EINTR в ctld, sysctl generation, devd-зависимости, force_depends
в mountd/nfsd rc, pmbr-datadisk). То есть перенос базовой ОС на FreeBSD 14/15 — это не «портировать
форк ядра», а «перенести горсть патчей».

**Основная работа — не в base, а в обвязке.** Дельта middleware у dravanet — 69 коммитов,
147 файлов: совместимость с новыми версиями Python в дереве портов, Samba 4.20→4.23,
OpenZFS 2.2→2.4, py-netif/py-bsd/py-libzfs, netsnmpagent, PAM без OPIE, порты, которые
переименовали/выкинули из апстрима (`www/novnc-websockify` → `devel/py-websockify`), сборка
webui, поведение rc-скриптов на новом sh. Плюс отказ от собственного форка ports в пользу
квартальных веток FreeBSD — это разово дорого, но убирает главный источник гниения.

## 6. Практический план

### Вариант A (рекомендуемый) — взять готовый живой форк

На сборочной машине с FreeBSD (у dravanet сборка идёт из-под свежей базы; официальный README
всё ещё требует FreeBSD 13.x — этот пункт надо проверить на месте):

```sh
pkg install -y git
git clone -b master-dravanet https://github.com/dravanet/truenas-core-build /usr/build
cd /usr/build
make bootstrap-pkgs
python3 -m ensurepip && pip3 install six
make checkout
make release
```

На выходе — ISO и upgrade-файл в `freenas/_BE/release/`. Дальше — либо чистая установка с ISO,
либо `System → Update → Install manual update file` на существующей 13.x-инсталляции.

### Вариант B — свой ребейз (если нужен контроль или другая целевая версия)

1. В `truenas-core/os` взять диапазон `merge-base(truenas/13.3-stable, upstream/stable/13)..truenas/13.3-stable`,
   отбросить вендорные и уже-апстримные коммиты, оставшиеся 7–15 патчей наложить на
   `upstream/releng/15.1` (или stable/14, если нужна более длинная поддержка — EOL 30.11.2028).
2. Ports: не тащить `truenas/ports`, а взять квартальную ветку `freebsd-ports` (2026Q2/Q3)
   и наложить сверху `middleware/nas_ports/`.
3. Middleware: взять `dravanet-middleware` как референс — там уже разобраны почти все конфликты
   с новым деревом портов; свои изменения класть поверх.
4. В `build/profiles/freenas/repos.pyd` прописать свои URL/ветки, в `kernel/TRUENAS.amd64`
   сверить список модулей с новым ядром.

### Доставка на существующие инсталляции

* Разовая — manual update tar через GUI/`freenas-update`, шага подписи в core-build нет.
* Постоянная — свой update-трейн: `freenas-pkgtools` + свой сервер манифестов; в Makefile.inc1
  цели `update-push`/`release-push` заточены под инфраструктуру iX, их надо заменить на свою.
  Клиенты переключаются сменой train в `/data/update.conf`/настройках обновления.

## 7. Риски и подводные камни

* **OpenZFS feature flags необратимы.** 13.3 идёт с OpenZFS 2.2, у dravanet — 2.4.3. После
  `zpool upgrade` откат на официальный CORE или на старую сборку невозможен. Пул не апгрейдить,
  пока новая сборка не проверена; и это же ломает обратный путь на TrueNAS SCALE/CE старых версий.
* **Юридическое.** Кодовая база под лицензией iX (`LICENSE.IX`), брендинг TrueNAS —
  торговая марка. zVault уже получил претензию по копирайту. Для личного/внутреннего
  использования проблем нет, для публикации ISO — вычищать брендинг и проприетарные куски.
* **iocage и плагины.** Индекс плагинов iX больше не обновляется; jail'ы придётся вести
  на своём индексе (как сделали в `zvaultio/iocage-plugin-index`) или переходить на bastille.
* **releng/15.0 EOL 30.09.2026** — если брать сборку dravanet как есть, вскоре потребуется
  перенос на 15.1/stable/15. Для «поставил и забыл» стабильнее целиться в stable/14 (до 2028)
  или stable/15 (до 2029).
* **HA/Enterprise-функциональность** (ixnvdimm, failover) в community-форках не поддерживается
  и не тестируется.
