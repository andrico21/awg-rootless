#!/bin/bash
set -euo pipefail

if [[ ! -f "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then
  echo "Error: server config not found: ${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" >&2
  exit 1
fi

printf "%-128s %-45s %-18s %-25s\n" "Name" "PublicKey" "AllowedIPs" "CreatedAt"
printf "%-128s %-45s %-18s %-25s\n" "--------------------------------------------------------------------------------------------------------------------------------" "--------------------------------------------" "------------------" "---------------------"

awk '
  /^# Peer configuration for / {
      # flush previous record
      if (name != "") {
          peers[++count] = sprintf("%s %s %s %s", name, key, ip, created)
      }
      name = $5
      key = ip = created = ""
  }

  /^# CreatedAt:/ {
      created = gensub(/^# CreatedAt:[[:space:]]*/, "", 1)
  }

  /^\[Peer\]/ { inside=1; next }

  inside && /^PublicKey/  { key=$3 }
  inside && /^AllowedIPs/ { ip=$3; inside=0 }

  END {
      peers[++count] = sprintf("%s %s %s %s", name, key, ip, created)
      for (i=1;i<=count;i++) {
          split(peers[i], f)
          if (f[3] != "")
              printf "%-128s %-45s %-18s %-25s\n", f[1], f[2], f[3], f[4]
      }
  }
' "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" | sort -k4,4r
