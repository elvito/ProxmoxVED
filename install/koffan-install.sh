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

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  golang-go
msg_ok "Installed Dependencies"

msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/PanSalut/Koffan/releases/latest | grep "tag_name" | sed -E 's/[^0-9.]//g')
curl -fsSL "https://github.com/PanSalut/Koffan/archive/refs/tags/v${RELEASE}.tar.gz" | tar -xz
mv ${APPLICATION}-${RELEASE}/ /opt/koffan
cd /opt/koffan
go build -o koffan main.go
cat <<EOF >/opt/.env
APP_ENV=production
APP_PASSWORD=shopping123
PORT=3000
EOF
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
EnvironmentFile=/opt/.env
WorkingDirectory=/opt/koffan
ExecStart=/opt/koffan/koffan
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
