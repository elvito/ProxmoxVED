#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ProxmoxVED Community
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://aliasvault.net

APP="AliasVault"
var_tags="${var_tags:-security;passwords;privacy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/aliasvault ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "aliasvault" "aliasvault/aliasvault"; then
    RELEASE=$(get_latest_github_release "aliasvault/aliasvault")

    msg_info "Stopping Services"
    cd /opt/aliasvault
    $STD docker compose down
    msg_ok "Stopped Services"

    msg_info "Updating Compose Configuration"
    curl -fsSL "https://raw.githubusercontent.com/aliasvault/aliasvault/${RELEASE}/docker-compose.yml" |
      sed "s/:latest/:${RELEASE}/g" >/opt/aliasvault/docker-compose.yml
    curl -fsSL "https://raw.githubusercontent.com/aliasvault/aliasvault/${RELEASE}/docker-compose.letsencrypt.yml" \
      >/opt/aliasvault/docker-compose.letsencrypt.yml
    msg_ok "Updated Compose Configuration"

    msg_info "Pulling Updated Images"
    $STD docker compose -f /opt/aliasvault/docker-compose.yml pull
    msg_ok "Pulled Updated Images"

    msg_info "Starting Services"
    $STD docker compose -f /opt/aliasvault/docker-compose.yml up -d --force-recreate
    msg_ok "Started Services"

    echo "${RELEASE}" >~/.aliasvault
    sed -i "s/^ALIASVAULT_VERSION=.*/ALIASVAULT_VERSION=${RELEASE}/" /opt/aliasvault/.env
    msg_ok "Updated successfully to ${RELEASE}!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW} Admin Panel:${CL} ${TAB}${GATEWAY}${BGN}https://${IP}/admin${CL}"
echo -e "${INFO}${YW} Admin credentials were shown in the installation output above.${CL}"
