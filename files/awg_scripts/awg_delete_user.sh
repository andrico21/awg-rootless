#!/bin/bash
## Usage: awg_delete_user.sh <username>

set +H -euo pipefail

USER2DELETE="${1}"

name_regex='^[[:alnum:]_!:@()-]{1,128}$'
if [[ ! "${USER2DELETE}" =~ ${name_regex} ]]; then
  echo "Error: user name must be 1–128 chars, allowed: A–Z, a–z, 0–9, '_', '-', '@', ':', '!', '(', ')'" >&2
  exit 1
fi

if grep -q "# Peer configuration for ${USER2DELETE}" "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"; then
  echo "User ${USER2DELETE} found in ${WG_SERVER_CFG_DIR} configs, proceeding with removal..."

  awk -v user="${USER2DELETE}" '
  BEGIN { skip=0 }
  /^# Peer configuration for / {
    if (index($0, "# Peer configuration for " user) == 1) {
      skip=1; next
    } else if (skip==1) {
      skip=0
    }
  }
skip==0 { print }
' "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" > "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}.tmp" &&
mv "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}.tmp" "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"

  # Remove user config
#  echo "Removing ${USER2DELETE} files from ${WG_SERVER_CFG_DIR}/peers/"; ls -lhtr "${WG_SERVER_CFG_DIR}/peers/${USER2DELETE}".conf*
  echo "Removing ${USER2DELETE} files from ${WG_SERVER_CFG_DIR}/peers/"; (ls -lhtr "${WG_SERVER_CFG_DIR}/peers/${USER2DELETE}".conf* || true)
  rm -f "${WG_SERVER_CFG_DIR}/peers/${USER2DELETE}".conf*

  echo "User ${USER2DELETE} deleted."
else
  echo "User ${USER2DELETE} not found."
fi
