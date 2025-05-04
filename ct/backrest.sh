#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/garethgeorge/backrest

APP="Backrest"
var_tags="Backup"
var_cpu="1"
var_ram="512"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /usr/bin/local/backrest ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE=$(curl -fsSL https://api.github.com/repos/garethgeorge/backrest/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
    if [[ ! -f /${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /${APP}_version.txt)" ]]; then
    msg_info "Updating $APP..."
    systemctl stop backrest
    mkdir -p /temp
    curl -fsSL "https://github.com/garethgeorge/backrest/releases/download/${RELEASE}/linux-x64.zip" -o $temp_file
    tar -xzf "$temp_file" -C /temp
    systemctl start backrest
    msg_ok "$APP has been updated."
    else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}
start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9898${CL}"
