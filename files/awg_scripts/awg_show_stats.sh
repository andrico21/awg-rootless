#!/bin/bash
AWG_CONF="${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}"

awk -v conf="${AWG_CONF}" '
BEGIN {
  while ((getline line < conf) > 0) {
    if (line ~ /^# Peer configuration for /)
      name = substr(line, 26)
    else if (line ~ /^PublicKey = /)
      key = substr(line, 13)
    if (name != "" && key != "") {
      map[key] = name
      name = key = ""
    }
  }
  close(conf)
}
{
  if ($1 == "peer:" && ($2 in map))
    printf "peer: %s (%s)\n", map[$2], $2
  else
    print
}' < <(awg show)
