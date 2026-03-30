#!/bin/bash
## Usage: SERVERURL="<external_server_address_without_port>" SERVERPORT=<external_port_number> WG_CUSTOM_DNS="<custom_dnses_if_needed>" WG_CUSTOM_MTU=<custom_mtu_if_needed> awg_create_user_config.sh "<user_name_to_create>"

set +H -euo pipefail
# User parameters
# exported variables needed for `envsubst` (to refactor later)
export USER_NAME="${1:-TestUser}"

name_regex='^[[:alnum:]_!:@()-]{1,128}$'
if [[ ! "${USER_NAME}" =~ ${name_regex} ]]; then
  echo "Error: user name must be 1-128 chars, allowed: A-Z, a-z, 0-9, '_', '-', '@', ':', '!', '(', ')'" >&2
  exit 1
fi

# exported variables needed for `envsubst` (to refactor later)
export USER_KEY_PRIVATE="$(awg genkey)"
export USER_KEY_PUBLIC="$(echo ${USER_KEY_PRIVATE} | awg pubkey)"
export USER_PSK="$(awg genpsk)"
export WG_KEEPALIVE_SEC="${WG_KEEPALIVE_SEC:=0}"
export SERVER_ADDR_EXT="${SERVERURL:-"your_server_external_fqdn_or_address"}" SERVER_PORT="${SERVERPORT:-"51820"}"
export SERVER_KEY_PUBLIC="$(cat "${WG_SERVER_CFG_DIR}"/server_public.key)"
export SERVER_IP_INT=$(/bin/ipcalc -n "${WG_INTERNAL_SUBNET}" | awk -F'[.=]' '/NETWORK/ {print $2"."$3"."$4"."($5+1)}')
export WG_CUSTOM_DNS="${WG_CUSTOM_DNS:-$SERVER_IP_INT}"
USER_CFG_FILE="${WG_SERVER_CFG_DIR}/peers/${USER_NAME}.conf"

# Abort if this user already exists
if [ -f "${WG_SERVER_CFG_DIR}/peers/${USER_NAME}.conf" ]; then
  echo "Error: user '${USER_NAME}' already exists in ${WG_SERVER_CFG_DIR}/peers/, first delete the relevant user"
  exit 1
fi

if grep -q "# Peer configuration for ${USER_NAME}" "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"; then
  echo "Error: a peer section for '${USER_NAME}' already exists in ${WG_SERVER_CFG_FILE}, first please delete the relevant user"
  exit 1
fi

# get the next available IP
export USER_IP_INT="$(awg_get_available_ip.sh "${WG_INTERNAL_SUBNET}" "${WG_SERVER_CFG_DIR}")/32"

export USER_CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
umask 0137 && envsubst < "${WG_TPL_DIR}"/user_config.template > "${USER_CFG_FILE}"

# if custom MTU is defined and non-empty - add corresponding line to user config
[ -n "${WG_CUSTOM_MTU:-}" ] && sed -i "/^$/N;/^\n\[Peer\]/s/^\n//;/^\[Peer\]/i MTU = ${WG_CUSTOM_MTU}\n" "${USER_CFG_FILE}"

if [ -f "${WG_SERVER_CFG_DIR}/asc_settings.cfg" ]; then
  umask 0137 && awk -v asc_file="${WG_SERVER_CFG_DIR}/asc_settings.cfg" 'BEGIN { while ((getline l < asc_file) > 0) asc[++n] = l; close(asc_file) }
  /^\[Peer\]/ && !inserted { for (i = 1; i <= n; i++) print asc[i]; print ""; inserted=1 } { print }' "${USER_CFG_FILE}" > "${USER_CFG_FILE}.tmp" && mv "${USER_CFG_FILE}.tmp" "${USER_CFG_FILE}"
else
  echo " asc_settings.cfg not found in ${WG_SERVER_CFG_DIR}, skipping."
fi

echo >> "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" && envsubst < "${WG_TPL_DIR}"/peer_config_section.template >> "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"

cat "${USER_CFG_FILE}" | qrencode -o "${USER_CFG_FILE}.png"

# just safery measure to avoid garbage variables in the case of manual script execution
unset USER_NAME USER_KEY_PRIVATE USER_KEY_PUBLIC USER_PSK KEEPALIVE_SEC SERVER_ADDR_EXT SERVER_PORT SERVER_KEY_PUBLIC SERVER_IP_INT WG_CUSTOM_DNS
