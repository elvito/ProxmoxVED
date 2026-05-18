#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fleetdm/fleet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_mysql

MYSQL_DB_NAME="fleet" MYSQL_DB_USER="fleet" setup_mysql_db

msg_info "Installing Dependencies"
$STD apt install -y redis-server
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"

msg_info "Configuring Application"
chmod +x /opt/fleet/fleet
PRIVATE_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/fleet/.env
FLEET_MYSQL_ADDRESS=127.0.0.1:3306
FLEET_MYSQL_DATABASE=fleet
FLEET_MYSQL_USERNAME=fleet
FLEET_MYSQL_PASSWORD=${MYSQL_DB_PASS}
FLEET_SERVER_ADDRESS=0.0.0.0:8080
FLEET_SERVER_TLS=false
FLEET_SERVER_PRIVATE_KEY=${PRIVATE_KEY}
FLEET_REDIS_ADDRESS=127.0.0.1:6379
FLEET_LOGGING_JSON=true
EOF
msg_ok "Configured Application"

msg_info "Running Database Migrations"
set -a && source /opt/fleet/.env && set +a
$STD /opt/fleet/fleet prepare db --no-prompt
msg_ok "Ran Database Migrations"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fleet.service
[Unit]
Description=Fleet
After=network.target mysql.service redis-server.service
Requires=mysql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fleet
EnvironmentFile=/opt/fleet/.env
ExecStart=/opt/fleet/fleet serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fleet redis-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
