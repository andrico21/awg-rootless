#!/bin/bash
## Has no any prerequisites, only parameters validation
## Usage (env-var mode): ASC_Jc=.. ASC_Jmin=.. ASC_Jmax=.. ASC_S1=.. ASC_S2=.. ASC_H1=.. ASC_H2=.. ASC_H3=.. ASC_H4=.. awg_validate_asc.sh
## Usage (legacy positional): awg_validate_asc.sh <Jc> <Jmin> <Jmax> <S1> <S2> <H1> <H2> <H3> <H4>
## Optional env vars: ASC_S3, ASC_S4, ASC_I1..ASC_I5

AWG_DOCS_URL="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#configuration"

# Legacy positional args support: if 9 positional args given, map them to env vars
if [ $# -ge 9 ]; then
  ASC_Jc="${ASC_Jc:-$1}"
  ASC_Jmin="${ASC_Jmin:-$2}"
  ASC_Jmax="${ASC_Jmax:-$3}"
  ASC_S1="${ASC_S1:-$4}"
  ASC_S2="${ASC_S2:-$5}"
  ASC_H1="${ASC_H1:-$6}"
  ASC_H2="${ASC_H2:-$7}"
  ASC_H3="${ASC_H3:-$8}"
  ASC_H4="${ASC_H4:-$9}"
fi

validate_asc_h_values() {
  set -euo pipefail
  local values=("$@")

  # Check all defined and non-empty
  for val in "${values[@]}"; do
    if [[ -z "${val}" ]]; then
      echo "Error: One or more H-values are not defined/empty. Check '${AWG_DOCS_URL}' for more details." >&2
      return 1
    fi

    # Integer format: bare number (legacy)
    if [[ "${val}" =~ ^[0-9]+$ ]]; then
      if (( val < 1 || val > 4294967295 )); then
        echo "Error: H-value (${val}) is out of range (1-4294967295). Check '${AWG_DOCS_URL}' for more details." >&2
        return 1
      fi
    # Range format: N-N (new magic header spec)
    elif [[ "${val}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local range_start="${BASH_REMATCH[1]}"
      local range_end="${BASH_REMATCH[2]}"
      if (( range_start > 4294967295 || range_end > 4294967295 )); then
        echo "Error: H-value range (${val}) parts must be 0-4294967295. Check '${AWG_DOCS_URL}' for more details." >&2
        return 1
      fi
      if (( range_start > range_end )); then
        echo "Error: H-value range (${val}) start must be <= end. Check '${AWG_DOCS_URL}' for more details." >&2
        return 1
      fi
    else
      echo "Error: H-value (${val}) must be an integer or a range (N-N). Check '${AWG_DOCS_URL}' for more details." >&2
      return 1
    fi
  done

  # Check uniqueness
  local unique_count
  unique_count=$(printf '%s\n' "${values[@]}" | sort -u | wc -l)
  if (( unique_count != ${#values[@]} )); then
    echo "Error: H1, H2, H3, H4 values must be unique among each other. Check '${AWG_DOCS_URL}' for more details." >&2
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
    echo "Error: Non-numeric jitter variable(s). Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( Jc < 1 || Jc > 128 )); then
    echo "Error: Jc (${Jc}) must be 1-128. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( Jmin < 1 || Jmin >= Jmax )); then
    echo "Error: Jmin (${Jmin}) must be >=1 and < Jmax (${Jmax}). Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( Jmax < Jmin || Jmax > Jmaxmax )); then
    echo "Error: Jmax (${Jmax}) must be > Jmin (${Jmin}) and <= MTU (${WG_CUSTOM_MTU}). Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  fi
  echo "Valid jitter parameters: Jc=${Jc} (1..128); Jmin=${Jmin} (1..${Jminmax}); Jmax=${Jmax} (${Jmaxmin}..${Jmaxmax})"
  return 0
}

validate_asc_s_values() {
  set -euo pipefail
  local S1="${1}"
  local S2="${2}"
  local S3="${3:-}"
  local S4="${4:-}"
  local S1max=$((WG_CUSTOM_MTU-148)) # maximal-accepted S1 value
  local S2max=$((WG_CUSTOM_MTU-92)) # maximal-accepted S2 value
  if [ -z "${S1}" ] || [ -z "${S2}" ]; then
    echo "Error: Missing S-values (S1, S2 are required). Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif ! [[ "${S1}" =~ ^[0-9]+$ && "${S2}" =~ ^[0-9]+$ ]]; then
    echo "Error: Non-numeric S-value. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( S1 < 1 || S1 > S1max )); then
    echo "Error: S1 (${S1}) must be 1-${S1max}. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( S2 < 1 || S2 > S2max )); then
    echo "Error: S2 (${S2}) must be >=1 and <=${S2max}. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
  elif (( S1 + 56 == S2 )); then
    echo "Error: Invalid relation - S1+56 must NOT equal S2 (S1=${S1}, S2=${S2}). Check '${AWG_DOCS_URL}' for more details." >&2
    return 1
  fi
  local s_msg="Valid S parameters: S1=${S1} (1..${S1max}); S2=${S2} (1..${S2max}, excluding $((S1+56)))"

  # S3 - optional, uint16 (0-65535)
  if [ -n "${S3}" ]; then
    if ! [[ "${S3}" =~ ^[0-9]+$ ]]; then
      echo "Error: S3 (${S3}) is not a number. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
    elif (( S3 > 65535 )); then
      echo "Error: S3 (${S3}) must be 0-65535. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
    fi
    s_msg="${s_msg}; S3=${S3} (0..65535)"
  fi

  # S4 - optional, uint16 (0-65535)
  if [ -n "${S4}" ]; then
    if ! [[ "${S4}" =~ ^[0-9]+$ ]]; then
      echo "Error: S4 (${S4}) is not a number. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
    elif (( S4 > 65535 )); then
      echo "Error: S4 (${S4}) must be 0-65535. Check '${AWG_DOCS_URL}' for more details." >&2; return 1
    fi
    s_msg="${s_msg}; S4=${S4} (0..65535)"
  fi

  echo "${s_msg}"
  return 0
}

validate_asc_i_values() {
  set -euo pipefail
  local i_validated=()
  local idx
  for idx in 1 2 3 4 5; do
    local val="${!idx:-}"
    if [ -n "${val}" ]; then
      # Must not contain newlines (would break config file format)
      if [[ "${val}" == *$'\n'* ]]; then
        echo "Error: I${idx} value must not contain newlines. Check '${AWG_DOCS_URL}' for more details." >&2
        return 1
      fi
      i_validated+=("I${idx}=${val}")
    fi
  done
  if [ ${#i_validated[@]} -gt 0 ]; then
    echo "Valid I parameters: ${i_validated[*]}"
  fi
  return 0
}

validate_asc_jitter_params "${ASC_Jc}" "${ASC_Jmin}" "${ASC_Jmax}"
validate_asc_s_values "${ASC_S1}" "${ASC_S2}" "${ASC_S3:-}" "${ASC_S4:-}"
validate_asc_h_values "${ASC_H1}" "${ASC_H2}" "${ASC_H3}" "${ASC_H4}"
validate_asc_i_values "${ASC_I1:-}" "${ASC_I2:-}" "${ASC_I3:-}" "${ASC_I4:-}" "${ASC_I5:-}"
