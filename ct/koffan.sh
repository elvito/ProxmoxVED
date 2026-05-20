#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/AminGholizad/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Amin Gholizad
# License: MIT | https://github.com/AminGholizad/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/PanSalut/Koffan

APP="Koffan"
var_tags="productivity"
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="13"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/koffan/koffan ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -s https://api.github.com/repos/PanSalut/Koffan/releases/latest | grep "tag_name" | sed -E 's/[^0-9.]//g')
    if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
        msg_info "Stopping $APP"
        systemctl stop koffan.service
        msg_ok "Stopped $APP"

        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/koffan/
        msg_ok "Backup Created"

        msg_info "Updating $APP to ${RELEASE}"
        curl -fsSL "https://github.com/PanSalut/Koffan/archive/refs/tags/v${RELEASE}.tar.gz" | tar -xz
        mv ${APP}-${RELEASE}/ /opt/koffan
        cd /opt/koffan
        go build -o $APP main.go

        msg_ok "Updated $APP to v${RELEASE}"

        msg_info "Starting $APP"
        systemctl start $APP.service
        msg_ok "Started $APP"

        msg_info "Cleaning Up"
        # nothing to clean
        msg_ok "Cleanup Completed"

        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Update Successful"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${INFO}${YW} The default password is: shopping123${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
