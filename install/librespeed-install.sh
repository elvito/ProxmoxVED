#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/librespeed/speedtest-go

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  golang
  msg_ok "Installed Dependencies"

msg_info "Installing Umlautadaptarr"
temp_file=$(mktemp)
RELEASE=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest-go/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
curl -fsSL "https://github.com/librespeed/speedtest-go/releases/download/v${RELEASE}/speedtest-go_${RELEASE}_darwin_amd64.tar.gz" -o $temp_file
###unzip -qj $temp_file '*/**' -d /opt/UmlautAdaptarr
echo "${RELEASE}" >"/opt//librespeed/librespeed_version.txt"
msg_ok "Installation completed"

msg_info "Downloading settings.toml"
curl -fsSL https://raw.githubusercontent.com/librespeed/speedtest-go/master/settings.toml -o /opt/librespeed/settings.toml
msg_ok "settings.toml downloaded"

msg_info "Creating systemd Service"
cat <<EOF >/etc/systemd/system/librespeed.service
[Unit]
Description=librespeed Service
After=network.target

[Service]
WorkingDirectory=/opt/librespeed
### ExecStart=/usr/bin/dotnet /opt/librespeed/
Restart=always
User=root
Group=root
### Environment=

[Install]
WantedBy=multi-user.target
EOF
systemctl -q --now enable librespeed
msg_ok "Created systemd Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $temp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
