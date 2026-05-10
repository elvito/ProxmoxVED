#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin (steveonjava)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://hermes-agent.nousresearch.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Creating Hermes User"
useradd -m -s /bin/bash hermes
loginctl enable-linger hermes
msg_ok "Created Hermes User"

msg_warn "WARNING: This script will run an external installer from a third-party source (https://hermes-agent.nousresearch.com/)."
msg_warn "The following code is NOT maintained or audited by our repository."
msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://hermes-agent.nousresearch.com/install.sh"
echo
read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  msg_error "Aborted by user. No changes have been made."
  exit 10
fi

msg_info "Installing Hermes Agent"
$STD setsid --wait env \
  HOME=/home/hermes \
  PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash <(curl -fsSL https://hermes-agent.nousresearch.com/install.sh) --skip-setup --hermes-home /home/hermes/.hermes --dir /home/hermes/.hermes/hermes-agent

chown -R hermes:hermes /home/hermes
git config --system --add safe.directory /home/hermes/.hermes/hermes-agent 2>/dev/null || true
msg_ok "Installed Hermes Agent"

msg_info "Installing Web Dashboard"
$STD runuser -u hermes -- \
  env HOME=/home/hermes VIRTUAL_ENV=/home/hermes/.hermes/hermes-agent/venv \
  /home/hermes/.local/bin/uv pip install 'hermes-agent[web,pty]'
msg_ok "Installed Web Dashboard"

msg_info "Configuring API Server"
API_SERVER_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
cat <<EOF >/home/hermes/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=${API_SERVER_KEY}
HERMES_REDACT_SECRETS=true
HERMES_HOME=/home/hermes/.hermes
HOME=/home/hermes
PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_OPTIONS=--max-old-space-size=3072
EOF
chmod 600 /home/hermes/.hermes/.env
chown hermes:hermes /home/hermes/.hermes/.env
chmod 750 /home/hermes
chmod 700 /home/hermes/.hermes
msg_ok "Configured API Server"

msg_info "Creating Dashboard Service"
cat <<EOF >/etc/systemd/system/hermes-dashboard.service
[Unit]
Description=Hermes Agent Web Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hermes
Group=hermes
UMask=0077
WorkingDirectory=/home/hermes
ExecStart=/home/hermes/.local/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open
EnvironmentFile=/home/hermes/.hermes/.env
Restart=on-failure
RestartSec=5
ProtectProc=invisible
ProcSubset=pid

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hermes-dashboard
msg_ok "Created Dashboard Service"

msg_info "Configuring Login Hints"
cat <<'HINT' >/etc/profile.d/hermes-hint.sh
if [[ "$(id -u)" -eq 0 ]]; then
  echo "  Run 'su - hermes' to manage Hermes Agent and profiles."
fi
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "  Dashboard: ssh -fNL 9119:localhost:9119 root@${LOCAL_IP}"
echo "             then open http://localhost:9119"
HINT
msg_ok "Configured Login Hints"

motd_ssh
customize
cleanup_lxc
