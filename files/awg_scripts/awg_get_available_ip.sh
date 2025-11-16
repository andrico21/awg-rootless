#!/bin/sh

## Usage: awg_get_available_ip.sh <CIDR> <wireguard_config_dir>
## example: awg_get_available_ip.sh 192.168.254.0/24 /etc/wireguard/config

set -eu

validate_cidr_format() {
  local CIDR="${1}"
  if ! echo "${CIDR}" | grep -Eq '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])/(3[0-2]|[12]?[0-9])$'; then
    echo "Invalid CIDR: ${CIDR}, a.b.c.d/e format expected" >&2
    return 1
  fi
}

get_next_ip() {
  local CIDR="${1}"
  local CONFIG_DIR="${2}"

  validate_cidr_format "${1}"

  # Find network and broadcast addresses (ipcalc)
  eval "$(ipcalc -b -n "${CIDR}")"
  [ -n "${NETWORK:-}" ] && [ -n "${BROADCAST:-}" ] || {
      echo "ipcalc failed for ${CIDR}: expected to return both NETWORK and BROADCAST values, but returned the following $(ipcalc -b -n "${CIDR}")" >&2; return 1;
  }

  # Gather all used IPs (without /32)
  local USED_IPS="$(grep -hR "Address" "${CONFIG_DIR}"/*.conf "${CONFIG_DIR}"/peers/*.conf 2>/dev/null | awk -F= '{gsub(/ /,""); print $2}' | sed 's#/.*##' | sort -u)"

  # IP increment function
  increment_ip() {
    IFS=. read -r a b c d <<EOF
${1}
EOF
    d=$((d+1))
    if [ "${d}" -gt 255 ]; then d=0; c=$((c+1)); fi
    if [ "${c}" -gt 255 ]; then c=0; b=$((b+1)); fi
    if [ "${b}" -gt 255 ]; then b=0; a=$((a+1)); fi
    printf "%d.%d.%d.%d" "${a}" "${b}" "${c}" "${d}"
  }

  # Compare IP 1 (current one) <= IP 2 (broadcast address)
  ip_is_less() {
    IFS=. read -r a1 b1 c1 d1 <<EOF
${1}
EOF
    IFS=. read -r a2 b2 c2 d2 <<EOF
${2}
EOF
    [ "${a1}" -lt "${a2}" ] && return 0
    [ "${a1}" -gt "${a2}" ] && return 1
    [ "${b1}" -lt "${b2}" ] && return 0
    [ "${b1}" -gt "${b2}" ] && return 1
    [ "${c1}" -lt "${c2}" ] && return 0
    [ "${c1}" -gt "${c2}" ] && return 1
    [ "${d1}" -le "${d2}" ]
  }

  local CURRENT_IP
  CURRENT_IP=$(increment_ip "${NETWORK}")   # skip network address by incrementing it in the beginning

  while ip_is_less "${CURRENT_IP}" "${BROADCAST}"; do
    # skip broadcast explicitly
    [ "${CURRENT_IP}" = "${BROADCAST}" ] && break
    # check if address is used - i.e. matching with existing users' addresses
    if ! echo "${USED_IPS}" | grep -qx "${CURRENT_IP}"; then
      echo "${CURRENT_IP}"
      return 0
    fi
    CURRENT_IP=$(increment_ip "${CURRENT_IP}")
    done

  echo "No free IPs in ${CIDR} network" >&2
  return 2
}

get_next_ip "${1}" "${2}"
