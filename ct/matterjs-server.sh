#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/matter-js/matterjs-server

APP="MatterJS-Server"
var_tags="${var_tags:-matter;iot;smarthome;homeassistant}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/matter-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(npm list -g matter-server --depth=0 2>/dev/null | grep matter-server | sed 's/.*@//')
  LATEST=$(npm show matter-server version 2>/dev/null)
  if [[ "$CURRENT" == "$LATEST" ]]; then
    msg_ok "No update required. ${APP} is already at v${LATEST}"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop matterjs-server
  msg_ok "Stopped Service"

  msg_info "Updating ${APP} to v${LATEST}"
  $STD npm install -g matter-server
  msg_ok "Updated ${APP} to v${LATEST}"

  msg_info "Starting Service"
  systemctl start matterjs-server
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5580${CL}"
