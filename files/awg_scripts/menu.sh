#!/bin/bash
set +H -eui pipefail

COLOR_RED=$'\e[31m'
COLOR_LRED=$'\e[91m'
COLOR_LYELLOW=$'\e[93m'
COLOR_LGREEN=$'\e[92m'
COLOR_NO=$'\e[0m'

main_menu() {
  while true; do
    clear
    echo "=== AmneziaWG server management  ==="
    echo
    echo -n "1) Create server config" && if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo -n " (${COLOR_LGREEN}existing one found${COLOR_NO})"; fi; echo
    if [[ ! -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "${COLOR_LYELLOW}First, you have to create server config${COLOR_NO}"; fi
    if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "2) Create new user"; fi
    if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "3) List users"; fi
    if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "4) Delete user"; fi
    if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "5) Show stats"; fi
    if [[ -s "${WG_SERVER_CFG_DIR}/${WG_SERVER_CFG_FILE}" ]]; then echo "6) Reload AmneziaWG configuration (${COLOR_LYELLOW}will drop existing connections${COLOR_NO})"; fi
    echo "7) Exit"
    echo; read -rp "Select option: " USER_CHOICE

    case "${USER_CHOICE}" in
      1)
        echo "== Create server config =="
        if ! awg_create_server_config.sh; then
          read -rp "It seems config is already present, ${COLOR_RED}do you really want to overwrite it?${COLOR_NO} [y/N]: " user_answer
          [[ "$user_answer" =~ ^[Yy]$ ]] && { awg_create_server_config.sh --force; continue; }
        fi
        read -rp "Press Enter to continue..."
        ;;
      2)
        read -rp "Enter new user name: " USER2CREATE
        [ -z "${USER2CREATE}" ] && { echo "Empty user name"; sleep 1; continue; }
        awg_create_user_config.sh "${USER2CREATE}" || { sleep 1; continue; }
        read -rp "Press Enter to continue..."
        ;;
      3)
        echo "== Show existing users list =="
        awg_list_users.sh
        echo
        read -rp "Press Enter to continue..."
        ;;
      4)
        echo "== Show existing users list =="
        awg_list_users.sh
        read -rp "Enter user name to delete (leave empty to abort): " USER2DELETE
        [ -z "${USER2DELETE}" ] && { echo "Invalid user name"; sleep 1; continue; }
        awg_delete_user.sh "${USER2DELETE}" || { sleep 1; continue; }
        read -rp "Press Enter to continue..."
        ;;
      5)
        awg_show_stats.sh
        read -rp "Press Enter to continue..."
        ;;

      6)
        [[ -z "$(awg show 2>/dev/null)" ]] && echo "Enabling AWG interface" && awg-quick up awg0 && continue
        read -rp "Reload AmneziaWG configuration (${COLOR_LYELLOW}will drop existing connections${COLOR_NO}) [y/N]: " user_answer
        [[ "${user_answer}" =~ ^[Yy]$ ]] && { awg-quick down awg0; awg-quick up awg0; continue; }
        ;;
      7)
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid selection"
        sleep 1
        ;;
    esac
  done
}

main_menu
