#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rclone/rclone

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apk add --no-cache \
  unzip \
  apache2-utils
msg_ok "Installed dependencies"

msg_info "Installing rclone"
temp_file=$(mktemp)
mkdir -p /opt/rclone
RELEASE=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RELEASE}/rclone-v${RELEASE}-linux-amd64.zip" -o $temp_file
unzip -j $temp_file '*/**' -d /opt/rclone
cd /opt/rclone
PASSWORD=$(head -c 16 /dev/urandom | xxd -p -c 16)
htpasswd -cb -B login.pwd admin $PASSWORD
{
  echo "rclone-Credentials"
  echo "rclone User Name: admin"
  echo "rclone Password: $PASSWORD"
} >>~/rclone.creds
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
rm -f $temp_file
msg_ok "Installed rclone"

msg_info "Enabling rclone Service"
cat <<EOF >/etc/init.d/rclone
#!/sbin/openrc-run
description="rclone Service"
command="/opt/rclone/rclone"
command_args="rcd --rc-web-gui --rc-web-gui-no-open-browser --rc-addr :3000 --rc-htpasswd /opt/rclone/login.pwd"
command_user="root"
pidfile="/var/run/rclone.pid"

depend() {
    use net
}
EOF
chmod +x /etc/init.d/rclone
$STD rc-update add rclone default
msg_ok "Enabled rclone Service"

msg_info "Starting rclone"
$STD service rclone start
msg_ok "Started rclone"

motd_ssh
customize
