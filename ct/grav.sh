#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/rafspiny/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Raffaele [rafspiny]
# License: MIT | https://github.com/rafspiny/ProxmoxVED/raw/main/LICENSE
# Source: https://getgrav.org/

APP="Grav"
var_tags="${var_tags:-cms}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

# Internal helper variables
INSTALLATION_CHECK_PATH="/opt/grav"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d [INSTALLATION_CHECK_PATH] ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "grav" "getgrav/grav"; then
        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" ${INSTALLATION_CHECK_PATH}
        msg_ok "Backup Created"

        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "grav" "getgrav/grav" "prebuild" "latest" "${INSTALLATION_CHECK_PATH}" "grav-update-v*zip"
        msg_ok "Update Successful"
    else
        msg_ok "No update required."
    fi
    exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
