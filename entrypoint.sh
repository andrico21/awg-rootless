#!/bin/sh
set -eu

COLOR_RED=$'\e[31m'
COLOR_LRED=$'\e[91m'
COLOR_LYELLOW=$'\e[93m'
COLOR_LGREEN=$'\e[92m'
COLOR_NO=$'\e[0m'
CHILD_PIDS=""

check_amneziawg() {
  echo "Checking if kernel module is available and loaded (Since I'm a rootless container - I cannot load kernel modules on my own)"
  lsmod | grep -q '^amneziawg' || { echo -e "Error: '${COLOR_LYELLOW}amneziawg${COLOR_NO}' kernel module isn't loaded - are you sure it's actually installed? Run '${COLOR_LYELLOW}lsmod | grep ^amneziawg${COLOR_NO}' on the host to check, more details '${COLOR_LYELLOW}https://github.com/amnezia-vpn/amneziawg-linux-kernel-module${COLOR_NO}' for more information. Exiting." >&2; exit 1; }
}

start_awg() {
  if [ -f "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]; then
    awg-quick up awg0
  else
    echo "Config missing: generating a new one" && awg_create_server_config.sh && awg-quick up awg0
  fi
}

start_coredns() {
  netstat -uln 2>/dev/null | grep ':53 ' || coredns -conf /etc/coredns/Corefile &
}

uptime_loop() { while true; do
    # placeholder, not doing anything
    uptime
    sleep 86400
  done
}

log2console_loop() {
  while true; do
    # placeholder, not doing anything
    #awg_log2console.sh
    sleep 60
  done
}

export2json_loop() {
  while true; do
    # for future enhancement - now just exporting users list to tmpfs-located .json
    awg_users2json.sh > /tmp/awgusers.json
    sleep 86400
    echo "Userlist saved to /tmp/awgusers.json (only available in current container instance)"
  done
}

cleanup() {
  echo "Stopping"
  awg-quick down awg0 >/dev/null 2>&1 || true
  [ -n "${CHILD_PIDS}" ] && kill ${CHILD_PIDS} 2>/dev/null || true
  exit 0
}

trap cleanup TERM INT

[ "${DNS_BUILTIN:-false}" = "true" ] && { start_coredns; [ -n "${!}" ] && CHILD_PIDS="${CHILD_PIDS} ${!}"; } || echo -e "Not starting built-in 'coredns' - set DNS_BUILTIN environment variable to 'true' to enable it"
[ "${LOG2CONSOLE:-false}" = "true" ] && { log2console_loop & CHILD_PIDS="${CHILD_PIDS} ${!}"; }
[ "${EXPORT2JSON:-false}" = "true" ] && { export2json_loop & CHILD_PIDS="${CHILD_PIDS} ${!}"; }
check_amneziawg && start_awg &
uptime_loop &
UPTIME_PID="${!}"
# Wait for first child to exit or for trap to run
wait "${UPTIME_PID}"
