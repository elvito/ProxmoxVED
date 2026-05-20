#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/matter-js/matterjs-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs

msg_info "Installing MatterJS-Server"
$STD npm install -g matter-server
mkdir -p /var/lib/matterjs-server
msg_ok "Installed MatterJS-Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/matterjs-server.service
[Unit]
Description=MatterJS Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/matter-server --storage-path /var/lib/matterjs-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now matterjs-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
