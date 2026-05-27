#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://snapotter.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  imagemagick \
  ghostscript \
  potrace \
  libopenjp2-tools \
  libegl1 \
  libwayland-client0 \
  libwayland-cursor0 \
  libwayland-egl1 \
  libxkbcommon0 \
  libxkbcommon-x11-0 \
  libxcursor1
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "caire" "esimov/caire" "prebuild" "latest" "/usr/local/bin" "caire-*-linux-amd64.tar.gz"

msg_info "Enabling pnpm"
$STD corepack enable
$STD corepack prepare pnpm@9.15.4 --activate
msg_ok "Enabled pnpm"

fetch_and_deploy_gh_release "snapotter" "snapotter-hq/SnapOtter" "tarball"

msg_info "Building SnapOtter"
mkdir -p /opt/snapotter/data/files
cd /opt/snapotter
$STD npm pkg delete scripts.prepare
$STD pnpm install --frozen-lockfile
$STD pnpm --filter @snapotter/web build
msg_ok "Built SnapOtter"

msg_info "Configuring SnapOtter"
cat <<EOF >/opt/snapotter/.env
PORT=1349
NODE_ENV=production
DB_PATH=/opt/snapotter/data/snapotter.db
WORKSPACE_PATH=/tmp/snapotter-workspace
FILES_STORAGE_PATH=/opt/snapotter/data/files
AUTH_ENABLED=true
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=admin
LOG_LEVEL=info
TRUST_PROXY=true
FILE_MAX_AGE_HOURS=72
CLEANUP_INTERVAL_MINUTES=60
EOF
mkdir -p /tmp/snapotter-workspace
msg_ok "Configured SnapOtter"

msg_info "Creating Service"
PNPM_BIN=$(which pnpm)
cat <<EOF >/etc/systemd/system/snapotter.service
[Unit]
Description=SnapOtter Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/snapotter
EnvironmentFile=/opt/snapotter/.env
ExecStart=${PNPM_BIN} --filter @snapotter/api run start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now snapotter
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
