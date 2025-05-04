#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/garethgeorge/backrest

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
  
msg_info "Installing Backrest"
temp_file=$(mktemp)
mkdir -p /temp
RELEASE=$(curl -s https://api.github.com/repos/garethgeorge/backrest/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
curl -fsSL "https://github.com/garethgeorge/backrest/releases/download/${RELEASE}/backrest_Linux_x86_64.tar.gz" -o $temp_file
tar -xvzf $temp_file /temp
mv /temp/backrest /usr/local/bin
echo "${RELEASE}" >"/backrest_version.txt"
msg_ok "Installation completed"

msg_info "Creating systemd Service"   
cat <<EOF >/etc/systemd/system/backrest.service
[Unit]
Description=Backrest
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/backrest
Environment="BACKREST_PORT=0.0.0.0:9898"

[Install]
WantedBy=multi-user.target
EOF
systemctl -q --now enable backrest
msg_ok "Created systemd Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $temp_file
rm -f /temp
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
