[English version](README.md).

В большинстве случаев `podman` взаимозаменяем с `docker` - существуют некоторые отличия в процессе сборки образа (как минимум разные имена файла с инструкциями: `Containerfile` против `Dockerfile`), но предсобранный образ работает идентично в обоих случаях.
### Отказ от ответственности :)
Данный проект носит характер хобби - он не про VPN или Амнезию как таковые, но больше про харденинг контейнеризованных приложений. Риск компрометации хоста или контейнера через Wireguard сам автор оценивает как ничтожно малый (стремящийся к нулю), скорее атака не исключена через сторонние приложения - например веб-панель для управления конфигами в том же контейнере. Поэтому проект служит больше как доказательство концепции запуска Wireguard-сервера (амнезия в т.ч.) в rootless-среде: в конце концов, это просто обвязка из скриптов для поднятия сетевого интерфейса, но как минимум это позволяет избежать лишнего процесса с root-привилегиями (да - это имеет смысл даже в пользовательском неймспейсе).
Проект зародился после того как используемый мной до этого образ [https://hub.docker.com/r/metaligh/amneziawg](https://hub.docker.com/r/metaligh/amneziawg)  перестал работать с последней версией модуля ядра AmneziaWG: поменялись входные параметры и упакованные в образ скрипты перестали работать. Исходников образа не нашлось - тогда и было решено пересобрать с нуля, а если уж пересобирать с нуля - то почему бы не попробовать сделать rootless.
Каждый из скриптов писался отдельно с прицелом на возможную автоматизацию, структура скриптов местами разная - честно говоря, под конец автор уже немного подзадолбался и включил ленивую жопу :) Да, каждый скрипт может использоваться отдельно от прочих (например - для массового создания пользователей) - требуемые параметры запуска перечислены в комментариях внутри скриптов. Автор пытался сделать вывод информации максимально подробным, чтобы облегчить сопровождение для новичков.
Замечание касательно размера образа - основная часть весит не более 40МБ, но `coredns` сам по себе добавляет более 70МБ сверху - при этом он совершенно опционален, если для пользователей не требуется разрешение имён средствами самого сервера - `coredns` можно убрать из списка пакетов на установку и пересобрать образ (в таком случае убедитесь, что переменная `DNS_BUILTIN` не установлена в `true` при запуске контейнера).
Тестировалось и отлаживалось на Ubuntu 24.04.

Проект выпущен под шуточной лицензией [IDGAF](LICENSE.txt): вы вольны делать всё, что вздумается - автору до лампочки :)
### Быстрый старт для ленивых (но пререквизиты ниже обязательны)
Взять готовый образ (пока не заливал):
```bash
podman pull amneziawg-rootless:latest
podman volume create amneziawg-cfg

podman run --detach --name awg-rootless --publish 3400:51820/udp -v amneziawg-cfg:/etc/amnezia/amneziawg/ \
 --cap-add net_admin --cap-add net_bind_service --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 \
 --env SERVERURL="some.lab.host" SERVERPORT="4430" amneziawg-rootless:latest

podman exec -it awg-rootless /bin/bash
menu.sh
```
или собрать самостоятельно:
```bash
git clone https://github.com/andrico21/awneziawg-rootless.git
cd awneziawg-rootless
podman build . -t awneziawg-rootless --no-cache --squash-all
podman image ls | grep amneziawg-rootless
```
### Пререквизиты
1. Модуль ядра `amneziawg` установленный на хосте: инструкции по ссылке https://github.com/amnezia-vpn/amneziawg-linux-kernel-module
2. Поскольку rootless-контейнер не может загружать модули ядра - убедитесь, что загружены заранее:
	- для проверки `lsmod | grep '^amneziawg'` - да, должен вернуть что-то в ответ
	- `sudo modprobe amneziawg` - разово загрузить вручную
	- `echo amneziawg | sudo tee /etc/modules-load.d/amneziawg.conf` - настроить загрузку модуля при запуске ОС (рекомендуемый способ)
### Переменные окружения
- `SERVERURL`: публичный адрес сервера, будет отражён в пользовательских конфигах
- `SERVERPORT`: доступный снаружи порт сервера, будет отражён в пользовательских конфигах
- Параметры безопасности для Амнезии (опционально): `ASC_Jc`, `ASC_Jmin`, `ASC_Jmax`, `ASC_S1`, `ASC_S2`, `ASC_H1`, `ASC_H2`, `ASC_H3`, `ASC_H4`. Если не определены - будут использованы значения по-умолчанию, зашитые в образ. Внутри есть процедура валидации значений для соотвествия логике, описанной в документации https://docs.amnezia.org/documentation/amnezia-wg/. После изменения параметров этой группы конфигурацию сервера нужно пересоздать (или руками поменять в конфигах).
- `WG_INTERNAL_SUBNET` (опционально, CIDR сети): можно указать желаемую подсеть для использования внутри туннеля - после изменения потребуется пересоздать конфигурацию сервера.
- `WG_CUSTOM_DNS` (опционально): если не определён - в качестве DNS для пользовательских конфигов будет использован внутренний адрес Wireguard-сервера. Свои можно указать в формате строки, разделитель - запятая: например `"8.8.8.8,1.1.1.1"`
- `DNS_BUILTIN` (опционально): если определена как `true` - запускать встроенный DNS-сервер, по умолчанию не запускается.
- `WG_CUSTOM_MTU` (опционально): по умолчанию MTU для пользователей установлен в 1280, если нужно иное - определить здесь, влияет только на новые пользовательские конфиги.
- `WG_KEEPALIVE_SEC` (опционально): keepalive-интервал для пользовательских конфигов. По-умолчанию 0.
- `EXPORT2JSON` (опционально): если определена как `true` - раз в сутки делает выгрузку пользователей в формате `json` в `/tmp/awgusers.json`, на текущий момент больше как заглушка для дальнейшей разработки, по-умолчанию отключено.
### Как это всё предполагается запускать
Можно использовать классический путь и запускать контейнер под `root` на хосте (как раз вариант с Docker по-умолчанию), но даже в этом варианте контейнер будет значительно более изолирован, чем с прочими найденными реализациями Wireguard в контейнерах. Помните, что при запуске от `root` местоположение томов с данными будет в `/var/lib/containers/` вместо пользовательской домашней директории (актуально дальше по тексту)

Иной (и значительно более безопасный в целом) вариант - полный rootless.

Создать нового пользователя без права на `sudo` (lingering требуется для запуска через т.н. квадлеты для `systemd`):
```bash
adduser awguser --shell /bin/false --disabled-password --comment "Rootless user to run AmneziaWG containers" \
 && loginctl enable-linger awguser
```
Запустить шелл под новым пользователем и сконфигурировать переменную окружения `XDG_RUNTIME_DIR` (требуется для корректной работы команд `systemctl --user`) + создать директорию для контейнер-юнитов
```bash
sudo -u awguser /bin/bash
echo "export XDG_RUNTIME_DIR=/run/user/$(id -u)" >> ~/.bashrc; export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p ~/.config/containers/systemd/
```
Далее в этом же шелле скачать или собрать образ, создать том для данных (или использовать bind директорий с хоста) и запустить контейнер.

Указать внешний адрес сервера и доступный извне порт в переменных `SERVERURL` и `SERVERPORT`. Внутри контейнера приложение использует стандартный порт `51820/udp` port - нужно лишь определить внешний, прописываемый в пользовательских конфигах.
```bash
podman pull amneziawg-rootless:latest
podman volume create amneziawg-cfg

podman run --detach --name awg-rootless --publish 4450:51820/udp \
 --mount=type=volume,source=amnez-test,destination=/etc/amnezia/amneziawg/,readonly=false,nodev,noexec,nosuid,chown=true \
 --cap-drop all --cap-add net_admin --cap-add net_bind_service --security-opt no-new-privileges --read-only \
 --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 \
 --env SERVERURL="myserver.google.com" --env SERVERPORT=4450 --env DNS_BUILTIN="true" \
 --env WG_INTERNAL_SUBNET="192.168.254.0/24" --env WG_CUSTOM_MTU=1320 amneziawg-rootless:latest
```
Логи контейнера:
```bash
podman logs -f awg-rootless
```
Интерактивное меню для работы с конфигами. Не забудьте перегрузить конфигурацию AmneziaWG после добавления/удаления пользователей (см. отдельный пункт в меню)
```bash
podman exec -it awg-rootless menu.sh
```
Конфиги доступны на хосте по пути `/home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/`, но поскольку контейнер работает под subuid rootless-пользователя - прямого доступа к ним с хоста нет: можно использовать `podman unshare` для доступа к конфигам (текстовый + QR-код), пример ниже:
```bash
ls -l /home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/
ls: cannot open directory '/home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg-demo/_data/peers/': Permission denied

podman unshare ls -l /home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/
total 8
-rw-r----- 1 65500 65500  453 Nov 16 13:05 test.conf
-rw-r----- 1 65500 65500 1540 Nov 16 13:05 test.conf.png

podman unshare cp .local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/test.conf* ~/
```
или проще достать из контейнера (пользователь `test` создан для демонстрации):
```bash
podman exec -it awg-rootless /bin/bash
1203ac6555aa:/etc/amnezia/amneziawg$ cat peers/test.conf
# test
# CreatedAt: 2025-11-16T13:05:44Z

[Interface]
...
```
### Квадлеты
Автор предпочитает запускать podman-контейнеры используя средства systemd - через т.н. квадлеты. Создайте пользовательский контейнер-юнит в директории `/home/awguser/.config/containers/systemd/`, опциональные параметры также оставлены для общей информации, но закомментированны:
```ini
# /home/awguser/.config/containers/systemd/amneziawg.container
[Container]
ContainerName=awg-rootless
Environment=SERVERURL=myserver.google.com SERVERPORT=4450
Image=amneziawg-rootless:latest
#PodmanArgs=--cpus 0.25 --memory 45mb
#Pull=newer

# networking
PublishPort=4450:51820/udp
Sysctl=net.ipv4.conf.all.src_valid_mark=1 net.ipv4.ip_forward=1

# storage
Mount=type=volume,source=amnez-test,destination=/etc/amnezia/amneziawg/,readonly=false,nodev,noexec,nosuid,chown=true

# security
AddCapability=net_admin net_bind_service
DropCapability=all
NoNewPrivileges=true
ReadOnly=true
#SeccompProfile=/usr/share/containers/awg_server_coredns.json

[Install]
WantedBy=default.target

[Unit]
Description=AmneziaWG server (rootless)
Wants=podman-user-wait-network-online.service
After=podman-user-wait-network-online.service

[Service]
Restart=on-failure
RestartSec=10s
```
Сохраните и перезагрузите конфигурацию демонов (важно - под пользователем! параметр `--user`):
```bash
systemctl --user daemon-reload && systemctl --user status awg-rootless.service
systemctl --user start awg-rootless.service
systemctl --user status awg-rootless.service
podman ps | grep awg-rootless
```
### Дополнительные функции
Автоматическое переиспользование свободных IP-адресов для новых пользователей - например, после удаления старых.

При пересоздании конфига скриптом автоматически выполняется резервное копирование уже имеющегося - для предотвращения случайной потери.
```bash
podman exec awg-rootless awg_create_server_config.sh --force
podman exec awg-rootless ls -l /etc/amnezia/amneziawg/backup/
total 8
-r--r----- 1 awg awg 749 Nov 16 17:06 backup_20251116_170618.tar.bz2
-r--r----- 1 awg awg 754 Nov 16 17:07 backup_20251116_170742.tar.bz2
```
Генерация `json` со списком пользователей
```bash
podman exec awg-rootless awg_users2json.sh
```
Предсозданный профиль Seccomp - доступен в директории `seccomp-profiles/` - всё ещё в статусе беты, но пока проблем не замечено.
Для использования с Seccomp скопировать профиль на хост, например в `/usr/share/containers/awg_server_coredns.json`, потом указать для контейнера используя параметр `--security-opt seccomp=/usr/share/containers/awg_server_coredns.json` (или директива `SeccompProfile` в systemd-юните)
### Известные проблемы
Если вы не знаете, что такое `pasta` - можно пропустить эту секцию :)

Не работает со штатной `pasta` из поставки Ubuntu 24.04 - убито несколько дней на траблшутинг, потом выяснилось, что с последней `pasta` всё же работает, если собрать из исходников - заведена issue https://github.com/containers/podman/issues/27541
```bash
podman run --detach --replace --name amnez-test --rm --network "pasta:-I,tap0,-U,auto,-u,3400:51820" -v amnez-test:/etc/amnezia/amneziawg/ --cap-add net_admin --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 amneziawg-rootless:latest
```
Со `slirp4netns` работает, от `pasta` ожидалось больше производительности, но в текущей версии с ней нормально не работает.
