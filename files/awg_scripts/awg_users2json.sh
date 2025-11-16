#!/bin/bash
set -euo pipefail

awk '
  # Start new record
  /^# Peer configuration for / {
      if (name != "") {
          emit(name, key, ip, created)
      }
      name=$5
      key=ip=created=""
  }

  /^# CreatedAt:/ {
      line=$0
      sub(/^# CreatedAt:[[:space:]]*/, "", line)
      created=line
  }

  /^\[Peer\]/ { inside=1; next }

  inside && /^PublicKey/  { key=$3 }
  inside && /^AllowedIPs/ { ip=$3; inside=0 }

  # Emit last
  END { emit(name, key, ip, created) }

  # JSON emitter
  function emit(n,k,i,c) {
      if (i == "") return
      printf("{\"name\":\"%s\",\"public_key\":\"%s\",\"allowed_ips\":\"%s\",\"created_at\":\"%s\"}\n", n,k,i,c)
  }
' "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" | jq --slurp '.' --sort-keys
