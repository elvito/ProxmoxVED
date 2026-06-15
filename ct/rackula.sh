#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: gVNS (ggfevans)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RackulaLives/Rackula

APP="Rackula"
var_tags="${var_tags:-homelab}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/rackula ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "rackula" "RackulaLives/Rackula"; then
    msg_info "Stopping Services"
    systemctl stop rackula-api nginx
    msg_ok "Stopped Services"

    create_backup /opt/rackula/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rackula" "RackulaLives/Rackula" "prebuild" "${var_version}" "/opt/rackula" "rackula-lxc-*.tar.gz"
    restore_backup

    msg_info "Updating Configuration"
    cp /opt/rackula/config/nginx.conf /etc/nginx/sites-available/rackula
    cp /opt/rackula/config/security-headers.conf /etc/nginx/snippets/security-headers.conf
    cp /opt/rackula/config/rackula-api.service /etc/systemd/system/rackula-api.service
    if grep -q '^User=' /etc/systemd/system/rackula-api.service; then
      sed -i 's/^User=.*/User=root/' /etc/systemd/system/rackula-api.service
    else
      sed -i '/^\[Service\]/a User=root' /etc/systemd/system/rackula-api.service
    fi
    if grep -q '^Group=' /etc/systemd/system/rackula-api.service; then
      sed -i 's/^Group=.*/Group=root/' /etc/systemd/system/rackula-api.service
    else
      sed -i '/^\[Service\]/a Group=root' /etc/systemd/system/rackula-api.service
    fi
    mkdir -p /etc/systemd/system/nginx.service.d
    cp /opt/rackula/config/nginx.service.d-override.conf /etc/systemd/system/nginx.service.d/override.conf
    chown -R root:root /opt/rackula/frontend
    find /opt/rackula/frontend -type d -exec chmod 755 {} \;
    find /opt/rackula/frontend -type f -exec chmod 644 {} \;
    chmod 750 /opt/rackula/data
    msg_ok "Updated Configuration"

    msg_info "Starting Services"
    if ! nginx -t >/dev/null 2>&1; then
      msg_error "nginx configuration test failed (run 'nginx -t' for details)"
      systemctl start nginx rackula-api || true
      exit 1
    fi
    systemctl start nginx rackula-api
    msg_ok "Started Services"

    msg_info "Verifying Services"
    for i in $(seq 1 10); do
      if curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1/api/health >/dev/null 2>&1; then
        msg_ok "Service running successfully"
        break
      fi
      if [ "$i" -eq 10 ]; then
        msg_info "Last rackula-api logs"
        journalctl -u rackula-api --no-pager -n 50 || true
        msg_error "Service failed to respond on http://127.0.0.1/api/health within 10 seconds"
        exit 1
      fi
      sleep 1
    done

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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
