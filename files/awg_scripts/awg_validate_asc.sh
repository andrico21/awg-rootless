#!/bin/bash
## Has no any prerequisites, only parameters validation
## Usage: validate_asc.sh <Jc> <Jmin> <Jmax> <S1> <S2> <H1> <H2> <H3> <H4>

validate_asc_h_values() {
  set -euo pipefail
  local values=("$@")

  # Check all defined and non-empty
  for val in "${values[@]}"; do
    if [[ -z "${val}" ]]; then
      echo "Error: One or more H-values are not defined/empty. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2
      return 1
    fi
    if ! [[ "${val}" =~ ^[0-9]+$ ]]; then
      echo "Error: H-value (${val}) is not a number. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2
      return 1
    fi
    if (( val < 1 || val > 2147483647 )); then
      echo "Error: H-value (${val}) is out of range (1–2147483647). Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2
      return 1
    fi
  done

  # Check uniqueness
  local unique_count
  unique_count=$(printf '%s\n' "${values[@]}" | sort -u | wc -l)
  if (( unique_count != ${#values[@]} )); then
    echo "Error: H1, H2, H3, H4 values must be unique among each other. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2
    return 1
  fi

  echo "H1, H2, H3, H4 values are valid."
  return 0
}

validate_asc_jitter_params() {
  set -euo pipefail
  local Jc="${1}"
  local Jmin="${2}"
  local Jmax="${3}"
  local Jminmax=$((Jmax-1)) # maximal-accepted Jmin value
  local Jmaxmin=$((Jmin+1)) # minimal-accepted Jmax value
  local Jmaxmax="${WG_CUSTOM_MTU}"
  if [ -z "${Jc}" ] || [ -z "${Jmin}" ] || [ -z "${Jmax}" ]; then
    echo "Error: Missing jitter variables." >&2; return 1
  elif ! [[ "${Jc}" =~ ^[0-9]+$ && "${Jmin}" =~ ^[0-9]+$ && "${Jmax}" =~ ^[0-9]+$ ]]; then
    echo "Error: Non-numeric jitter variable(s). Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( Jc < 1 || Jc > 128 )); then
    echo "Error: Jc (${Jc}) must be 1–128. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( Jmin < 1 || Jmin >= Jmax )); then
    echo "Error: Jmin (${Jmin}) must be ≥1 and < Jmax (${Jmax}). Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( Jmax < Jmin || Jmax > Jmaxmax )); then
    echo "Error: Jmax (${Jmax}) must be > Jmin (${Jmin}) and ≤ MTU (${WG_CUSTOM_MTU}). Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  fi
  echo "Valid jitter parameters: Jc=${Jc} (1..128); Jmin=${Jmin} (1..${Jminmax}); Jmax=${Jmax} (${Jmaxmin}..${Jmaxmax})"
  return 0
}

validate_asc_s_values() {
  set -euo pipefail
  local S1="${1}"
  local S2="${2}"
  local S1max=$((WG_CUSTOM_MTU-148)) # maximal-accepted S1 value
  local S2max=$((WG_CUSTOM_MTU-92)) # maximal-accepted S2 value
  if [ -z "${S1}" ] || [ -z "${S2}" ]; then
    echo "Error: Missing S-values. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif ! [[ "${S1}" =~ ^[0-9]+$ && "${S2}" =~ ^[0-9]+$ ]]; then
    echo "Error: Non-numeric S-value. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( S1 < 1 || S1 > S1max )); then
    echo "Error: S1 (${S1}) must be 1–${S1max}. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( S2 < 1 || S2 > S2max )); then
    echo "Error: S2 (${S2}) must be ≥1 and ≤${S2max}. Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2; return 1
  elif (( S1 + 56 == S2 )); then
    echo "Error: Invalid relation - S1+56 must NOT equal S2 (S1=${S1}, S2=${S2}). Check 'https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration' for more details." >&2
    return 1
  fi
  echo "Valid S parameters: S1=${S1} (1..${S1max}); S2=${S2} (1..${S2max}, excluding $((S1+56)))"
  return 0
}

validate_asc_jitter_params "${1}" "${2}" "${3}"
validate_asc_s_values "${4}" "${5}"
validate_asc_h_values "${6}" "${7}" "${8}" "${9}"
