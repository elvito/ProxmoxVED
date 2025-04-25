#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/elvito/ProxmoxVED/refs/heads/librespeed/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/librespeed/speedtest-go

APP="librespeed"
var_tags="speedtest"
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="11"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/librespeed/appsettings.json ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest-go/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
    if [[ ! -f /opt/librespeed/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt//librespeed/${APP}_version.txt)" ]]; then
    msg_info "Updating $APP..."
    systemctl stop librespeed
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/librespeed/speedtest-go/releases/download/v${RELEASE}/speedtest-go_${RELEASE}_darwin_amd64.tar.gz" -o $temp_file
    ###$STD unzip -u $temp_file '*/**' -d /opt/librespeed
    systemctl start librespeed
    msg_ok "$APP has been updated."
    else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}
start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
