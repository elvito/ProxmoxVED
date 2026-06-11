#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bookorbit/bookorbit

APP="BookOrbit"
var_tags="${var_tags:-books;library;reading}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bookorbit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bookorbit" "bookorbit/bookorbit"; then
    msg_info "Stopping Service"
    systemctl stop bookorbit
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/bookorbit/.env /opt/bookorbit.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball" "latest" "/opt/bookorbit-src"

    msg_info "Rebuilding Application"
    cd /opt/bookorbit-src
    $STD corepack enable
    $STD corepack prepare pnpm@10.32.1 --activate
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter client run build-only
    $STD pnpm --filter server run build
    rm -rf /opt/bookorbit-deploy
    $STD pnpm --filter server deploy --prod --legacy /opt/bookorbit-deploy
    cp -r /opt/bookorbit-src/server/dist /opt/bookorbit-deploy/dist
    mkdir -p /opt/bookorbit-deploy/migrations
    cp -r /opt/bookorbit-src/server/src/db/migrations/. /opt/bookorbit-deploy/migrations/
    cp -r /opt/bookorbit-src/client/dist /opt/bookorbit-deploy/public
    cp /opt/bookorbit-src/server/entrypoint.sh /opt/bookorbit-deploy/entrypoint.sh
    mkdir -p /opt/bookorbit-deploy/bin/kepubify
    cp -r /opt/bookorbit-src/server/bin/kepubify/. /opt/bookorbit-deploy/bin/kepubify/
    chmod +x /opt/bookorbit-deploy/entrypoint.sh /opt/bookorbit-deploy/bin/kepubify/*
    rm -rf /opt/bookorbit
    mv /opt/bookorbit-deploy /opt/bookorbit
    msg_ok "Rebuilt Application"

    msg_info "Updating Kobo Python Runtime"
    /opt/bookorbit-python/bin/python -m pip install --no-cache-dir -r /opt/bookorbit-src/server/requirements/kobo-cloudscraper.txt
    msg_ok "Updated Kobo Python Runtime"

    msg_info "Restoring Configuration"
    cp /opt/bookorbit.env.bak /opt/bookorbit/.env
    rm -f /opt/bookorbit.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start bookorbit
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
