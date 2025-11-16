#!/bin/bash

## variables to define in container ENV
## SERVERURL, SERVERPORT
## optionally: WG_INTERNAL_SUBNET, WG_SERVER_CFG_FILE, WG_CUSTOM_MTU

FORCE=0

WG_CUSTOM_MTU="${WG_CUSTOM_MTU:=1280}"

for arg in "${@}"; do
  case "${arg}" in
    --force) FORCE=1 ;;
    *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

if [ -e "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ] && [ "${FORCE}" -ne 1 ]; then
    echo -e "\e[31mError: ${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE} already exists, use with '--force' if really want to recreate configs.\e[0m" >&2
    exit 1
fi

if [ -e "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]; then
  echo -e "Backing up the existing server config..."
  # it's still possible to remove backups, but to avoid accidental changes - permissions set to 440. Umask is actually ignored by mktemp, that's why additional chmod applied.
  umask 0137 && tmpfile=$(mktemp) && tar --create --bzip2 --file "${tmpfile}" --exclude='*.png' --exclude="${WG_SERVER_CFG_DIR#/}/backup" "${WG_SERVER_CFG_DIR}" && chmod 0440 "${tmpfile}" && mv "${tmpfile}" "${WG_SERVER_CFG_DIR}"/backup/backup_$(date +%Y%m%d_%H%M%S).tar.bz2
fi

[ -e "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ] && echo "Cleaning up existing configs"
rm -f "${WG_SERVER_CFG_DIR}"/* "${WG_SERVER_CFG_DIR}"/peers/* 2>/dev/null

# Default values (use existing ones if set)
ASC_Jc="${ASC_Jc:=8}"
ASC_Jmin="${ASC_Jmin:=50}"
ASC_Jmax="${ASC_Jmax:=1000}"
ASC_S1="${ASC_S1:=15}"
ASC_S2="${ASC_S2:=150}"
ASC_H1="${ASC_H1:=1106457265}"
ASC_H2="${ASC_H2:=249455488}"
ASC_H3="${ASC_H3:=1209847463}"
ASC_H4="${ASC_H4:=1646644382}"

# check values supplied: exit with proper comments if wrong
WG_CUSTOM_MTU="${WG_CUSTOM_MTU}" awg_validate_asc.sh "${ASC_Jc}" "${ASC_Jmin}" "${ASC_Jmax}" "${ASC_S1}" "${ASC_S2}" "${ASC_H1}" "${ASC_H2}" "${ASC_H3}" "${ASC_H4}"

read -r -d '' ASC_BLOCK <<EOF
Jc = ${ASC_Jc}
Jmin = ${ASC_Jmin}
Jmax = ${ASC_Jmax}
S1 = ${ASC_S1}
S2 = ${ASC_S2}
H1 = ${ASC_H1}
H2 = ${ASC_H2}
H3 = ${ASC_H3}
H4 = ${ASC_H4}
EOF

[ -n "${WG_CUSTOM_MTU:-}" ] && { ! printf '%s' "${WG_CUSTOM_MTU}" | grep -Eq '^[0-9]+$' || [ "${WG_CUSTOM_MTU}" -lt 576 ] || [ "${WG_CUSTOM_MTU}" -gt 9216 ]; } && { echo "Error: invalid MTU (${WG_CUSTOM_MTU}); must be between 576 and 9216 bytes." >&2; exit 2; }

if [ -n "${ASC_BLOCK}" ]; then (umask 0137 && printf '%s\n' "${ASC_BLOCK}" > "${WG_SERVER_CFG_DIR}/asc_settings.cfg"); fi

export NET_IF_NAME="$(ls /sys/class/net | grep -v "lo\|awg" | head -n1)"
export SERVER_KEY_PRIVATE="$(awg genkey)"
export SERVER_KEY_PUBLIC="$(printf '%s' "${SERVER_KEY_PRIVATE}" | awg pubkey)"
export SERVER_ADDR_EXT="${SERVERURL:-"your_server_external_fqdn_or_address"}" SERVER_PORT="${SERVERPORT:-"51820"}"
export IP_SUBNET_TUN="${WG_INTERNAL_SUBNET:-"10.12.12.0/24"}"
export SERVER_IP_INT=$(/bin/ipcalc -n "${IP_SUBNET_TUN}" | awk -F'[.=]' '/NETWORK/ {print $2"."$3"."$4"."($5+1)}')

umask 177 && printf '%s\n' "${SERVER_KEY_PRIVATE}" > "${WG_SERVER_CFG_DIR}"/server_private.key
umask 137 && printf '%s\n' "${SERVER_KEY_PUBLIC}" > "${WG_SERVER_CFG_DIR}"/server_public.key
umask 137 && envsubst < "${WG_TPL_DIR}"/server_config.template > "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"

## there's no need to limit MTU for server itself - commented out, but left as a placeholder here
## [ -n "${WG_CUSTOM_MTU:-}" ] && echo "MTU=${WG_CUSTOM_MTU}" >> "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" && echo >> "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"

if [ -n "${ASC_BLOCK}" ]; then printf '%s\n' "${ASC_BLOCK}" >> "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"; fi

# sanitize environment from exported vars
unset NET_IF_NAME SERVER_KEY_PRIVATE SERVER_KEY_PUBLIC SERVER_ADDR_EXT IP_SUBNET_TUN SERVER_IP_INT
