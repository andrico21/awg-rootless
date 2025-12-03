[Russian version](README.rus.md).

[Dockerhub](https://hub.docker.com/r/andrico21/amneziawg-rootless)

In the most cases, `podman` is interchangeable with `docker` - yes, there're some difference in build-process, but pre-built image should work - just align command-line parameters (to be added to readme somewhat later).

### Disclaimer
This project is actually a hobby project made for fun - it's not about VPN or AmneziaWG, but mostly about hardening. Although I consider the risk of a compromise via WireGuard itself to be negligibly small (approaching zero), an attack could be performed out through its companion applications (like web-panels) running in the same container. This project is more about a **proof-of-concept** demo of running a WireGuard server in a rootless setup - after all, there's just a bunch of scripts to bring up the interface inside, but it removes yet another rootful process from the host and uses an isolated network namespace without affecting the host OS network (in the case of rootless host-user).

The project started when the well-known image [https://hub.docker.com/r/metaligh/amneziawg](https://hub.docker.com/r/metaligh/amneziawg) stopped working with the latest version of the AmneziaWG kernel module, and its source code could not be found in public access. Then I decided to rebuild it from scratch and if you are rebuilding something from scratch - why not to try to make it rootless right away.

Each script was written separately with potential automation in mind, so scripts' structure sometimes differs - a bit tired to polish that stuff, so lazy mode now. So yep, each script can be used independently (for example, for bulk users creation) - the required startup parameters are listed in the script's comments. I tried to make those with additional verbosity enough to guide operations.

Note about image's size: its base part is less than 40mb, but `coredns` component adds itself like ~70mb more - however, it's absolutely optional if you're not using AWG-server for name resolution. Just remove `coredns` installation from `Containerfile` and rebuild image + don't define `DNS_BUILTIN` environment variable for container.
Tested and debugged on Ubuntu 24.04.

Project is released under [IDGAF](LICENSE.txt) license: you're free to steal/borrow/change - whatever, let's make this world a bit more secure by default.

### Quick start for lazy arses (mind about prerequisites section below)
```bash
podman pull amneziawg-rootless:latest
podman volume create amneziawg-cfg

podman run --detach --name awg-rootless --publish 3400:51820/udp -v amneziawg-cfg:/etc/amnezia/amneziawg/ \
 --cap-add net_admin --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 \
 --env SERVERURL="some.lab.host" SERVERPORT="4430" amneziawg-rootless:latest

podman exec -it awg-rootless /bin/bash
menu.sh
```
or build an image by yourself:
```bash
git clone https://github.com/andrico21/awg-rootless.git
cd awg-rootless
podman build . -t awneziawg-rootless --no-cache --squash-all
podman image ls | grep amneziawg-rootless
```
### Prerequisites
1. `amneziawg` kernel module installed on host- check https://github.com/amnezia-vpn/amneziawg-linux-kernel-module
2. Since rootless container is unable to load any kernel modules - you have to ensure it's loaded in advance:
	- `amneziawg` loaded: `lsmod | grep '^amneziawg'` to check (should return something, yep)
	- `sudo modprobe amneziawg` - to load manually once
	- `echo amneziawg | sudo tee /etc/modules-load.d/amneziawg.conf` - to make it loaded automatically on boot (recommended)

### Environment variables
- `SERVERURL` (string): your public server name, reflected in user configs
- `SERVERPORT` (string): your public server AWG-port, reflected in user configs
- Advanced security configuration parameters (optional, AmneziaWG-specific): `ASC_Jc`, `ASC_Jmin`, `ASC_Jmax`, `ASC_S1`, `ASC_S2`, `ASC_H1`, `ASC_H2`, `ASC_H3`, `ASC_H4`. If not defined - hardcoded default values are used. There's a validation procedure inside to maintain logic described in https://docs.amnezia.org/documentation/amnezia-wg/ document. In case of changing this group of parameters you have to regenerate server configuration.
- `WG_INTERNAL_SUBNET` (optional, CIDR string): you can define custom tunnel-subnet - server configuration reset is required to apply new network settings
- `WG_CUSTOM_DNS` (optional, string): if not specified - container address will be used for new user configs. But it's possible to specify DNS servers like "8.8.8.8,1.1.1.1"
- `DNS_BUILTIN` (optional, string): if `true` - start builtin coredns server, `false` by default.
- `WG_CUSTOM_MTU` (optional, integer): by default, it's set to `1280` for new users, if need other - set this.
- `WG_KEEPALIVE_SEC` (optional, integer): default keepalive interval for new users. 0 by default.
- `EXPORT2JSON` (optional, string): if `true` - currently like placeholder for future improvements, makes daily users list export to `/tmp/awgusers.json` inside of container, `false` by default.
### How it's supposed to run
You can use the classic way and run container under host `root` user - even in this case it will be a way more confined than other implementations, just mind that volume location will be in `/var/lib/containers/` instead of user homedir.

Create new user without sudo-permissions (lingering is required to be enabled if you will run it using quadlets):
```bash
adduser awguser --shell /bin/false --disabled-password --comment "Rootless user to run AmneziaWG containers" \
 && loginctl enable-linger awguser
```
Run a shell with new user and configure `XDG_RUNTIME_DIR` variable (needed for `systemctl --user` commands)
```bash
sudo -u awguser /bin/bash
echo "export XDG_RUNTIME_DIR=/run/user/$(id -u)" >> ~/.bashrc; export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p ~/.config/containers/systemd/
```
Next, in the same shell pull an image, create volume (directory bind is also fine) and run.
Use an external address of your AWG-server as `SERVERURL` and externally available port as `SERVERPORT`. Inside of container application always uses the standard `51820/udp` port - so, you have to only define an external one for user-related configurations.
```bash
podman pull amneziawg-rootless:latest
podman volume create amneziawg-cfg

podman run --detach --name awg-rootless --publish 4450:51820/udp \
 --mount=type=volume,source=amnez-test,destination=/etc/amnezia/amneziawg/,readonly=false,nodev,noexec,nosuid,chown=true \
 --cap-drop all --cap-add net_admin --security-opt no-new-privileges --read-only \
 --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 \
 --env SERVERURL="myserver.google.com" --env SERVERPORT=4450 --env DNS_BUILTIN="true" \
 --env WG_INTERNAL_SUBNET="192.168.254.0/24" --env WG_CUSTOM_MTU=1100 amneziawg-rootless:latest
```
Container logs:
```bash
podman logs -f awg-rootless
```
Interactive menu to work with configs. Don't forget to reload AmneziaWG configuration after adding users (menu item #6).
```bash
podman exec -it awg-rootless menu.sh
```
Configs are available in `/home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/` directory, but since the container operates under rootless user subuid - its files are not available directly, use `podman unshare` to retrieve them (text config + its generated QR code representation):
```bash
ls -l /home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/
ls: cannot open directory '/home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg-demo/_data/peers/': Permission denied

podman unshare ls -l /home/awguser/.local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/
total 8
-rw-r----- 1 65500 65500  453 Nov 16 13:05 test.conf
-rw-r----- 1 65500 65500 1540 Nov 16 13:05 test.conf.png

podman unshare cp .local/share/containers/storage/volumes/amneziawg-cfg/_data/peers/test.conf* ~/
```
or easier to retrieve them from container (`test` user is created for demo):
```bash
podman exec -it awg-rootless /bin/bash
1203ac6555aa:/etc/amnezia/amneziawg$ cat peers/test.conf
# test
# CreatedAt: 2025-11-16T13:05:44Z

[Interface]
...
```
### Quadlet
I prefer to run podman containers via systemd quadlets, create user-scoped container-unit in `/home/awguser/.config/containers/systemd/` directory. I left some optional parameters commented for general awareness:
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
AddCapability=net_admin
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
Save and reload user daemons:
```bash
systemctl --user daemon-reload && systemctl --user status awg-rootless.service
systemctl --user start awg-rootless.service
systemctl --user status awg-rootless.service
```
<details>
  <summary>User mapping and caps demo: root vs rootless host user</summary>
  
  Running under host root - test container internal user is mapped to host rootless user's uid, only NET_ADMIN capability is added for user namespace:
  ```bash
  root@awg-test:~# podman top awg-rootless comm args pid hpid user huser group hgroup capeff capamb capbnd capinh capprm
  COMMAND        COMMAND                               PID         HPID        USER        HUSER       GROUP       HGROUP      EFFECTIVE CAPS  AMBIENT CAPS  BOUNDING CAPS  INHERITED CAPS  PERMITTED CAPS
  entrypoint.sh  /bin/sh /entrypoint.sh                1           20863       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  coredns        coredns -conf /etc/coredns/Corefile   2           20865       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  entrypoint.sh  /bin/sh /entrypoint.sh                3           20866       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  entrypoint.sh  /bin/sh /entrypoint.sh                5           20868       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  sleep          sleep 86400                           15          20878       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  sleep          sleep 86400                           18          20881       awg         65500       awg         65500       NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  ```

Running under host rootless user - container internal user is mapped to host rootless user' subuid range, only NET_ADMIN capability is added for user namespace
  ```bash
  podman top awg-rootless args pid hpid user huser group hgroup capeff capamb capbnd capinh capprm
  COMMAND                               PID         HPID        USER        HUSER       GROUP       HGROUP      EFFECTIVE CAPS  AMBIENT CAPS  BOUNDING CAPS  INHERITED CAPS  PERMITTED CAPS
  /bin/sh /entrypoint.sh                1           20399       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  coredns -conf /etc/coredns/Corefile   2           20401       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  /bin/sh /entrypoint.sh                3           20402       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  /bin/sh /entrypoint.sh                6           20405       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  sleep 86400                           14          20413       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  sleep 86400                           17          20416       awg         231035      awg         231035      NET_ADMIN       NET_ADMIN     NET_ADMIN      NET_ADMIN       NET_ADMIN
  ```
</details>

### Additional features
Automatic reusing of IP addresses for new users if there're released ones after user deletion.

Config reinitialization is supported with automatic backup to avoid accidental loss.
```bash
podman exec awg-rootless awg_create_server_config.sh --force
podman exec awg-rootless ls -l /etc/amnezia/amneziawg/backup/
total 8
-r--r----- 1 awg awg 749 Nov 16 17:06 backup_20251116_170618.tar.bz2
-r--r----- 1 awg awg 754 Nov 16 17:07 backup_20251116_170742.tar.bz2
```
Generate `json` with users list
```bash
podman exec awg-rootless awg_users2json.sh
```
Pre-generated seccomp-profile is available in seccomp-profiles/ directory - still in beta, but so far no problems.
Copy to `/usr/share/containers/awg_server_coredns.json`, then specify it for container using `--security-opt seccomp=/usr/share/containers/awg_server_coredns.json` (or use `SeccompProfile` directive in systemd container unit)

### Known issues
I spent several days to make it working with `pasta`/`passt`, but eventually discovered that it just doesn't work properly with Ubuntu 24.04's stock `pasta`, but works with the latest one compiled from sources - see issue https://github.com/containers/podman/issues/27541
```bash
podman run --detach --replace --name amnez-test --rm --network "pasta:-I,tap0,-U,auto,-u,3400:51820" -v amnez-test:/etc/amnezia/amneziawg/ --cap-add net_admin --sysctl net.ipv4.conf.all.src_valid_mark=1 --sysctl net.ipv4.ip_forward=1 amneziawg-rootless:latest
```
It works fine with `slirp4netns`, but more perfomance is expected with `pasta` (ideally, lol)
