#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Amin Gholizad
# License: MIT | https://github.com/AminGholizad/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/PanSalut/Koffan

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ensure_dependencies build-essential
setup_go

fetch_and_deploy_gh_release "koffan" "PanSalut/Koffan"

msg_info "Building Koffan"
cd /opt/koffan
go build -o koffan main.go
msg_ok "Building Completed"

msg_info "Configuring Koffan"
mkdir /opt/koffan/data
cat <<EOF >/opt/koffan/data/.env
APP_ENV=production
APP_PASSWORD=shopping123
PORT=3000
DB_PATH=/opt/koffan/data/shopping.db
EOF
msg_ok "Configuration Completed"

msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/koffan.service
[Unit]
Description=Koffan Service
After=network.target

[Service]
EnvironmentFile=/opt/koffan/data/.env
WorkingDirectory=/opt/koffan
ExecStart=/opt/koffan/koffan
Restart=always

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Service created"

msg_info "Finalizing Koffan installation"
systemctl enable -q --now koffan
motd_ssh
customize
msg_ok "Koffan installation complete"
cleanup_lxc
