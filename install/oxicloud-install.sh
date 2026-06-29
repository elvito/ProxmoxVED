#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DioCrafts/OxiCloud

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="oxicloud" PG_DB_USER="oxicloud" setup_postgresql_db
fetch_and_deploy_gh_release "OxiCloud" "DioCrafts/OxiCloud" "tarball" "latest" "/opt/oxicloud"
# Extract pinned Rust toolchain from Dockerfile (e.g. "FROM rust:1.96-alpine3.24" -> 1.96)
TOOLCHAIN="$(grep -oP 'FROM\s+rust:\K[0-9]+\.[0-9]+(\.[0-9]+)?' /opt/oxicloud/Dockerfile | head -1)"
RUST_TOOLCHAIN="${TOOLCHAIN:-stable}" setup_rust

msg_info "Building Frontend SPA"
cd /opt/oxicloud/frontend
$STD npm ci
$STD npm run build
msg_ok "Built Frontend SPA"

msg_info "Building OxiCloud (Patience)"
cd /opt/oxicloud
export DATABASE_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost/${PG_DB_NAME}"
export RUSTFLAGS="-C target-cpu=native"
# aws-sdk-s3 + aws-lc-sys can use ~1.5 GiB per rustc job under LTO+codegen-units=1.
# Cap concurrency by RAM to avoid SIGKILL on small containers (issue #1513).
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
CARGO_JOBS=$((RAM_MB / 1536))
[[ $CARGO_JOBS -lt 1 ]] && CARGO_JOBS=1
$STD cargo build --release -j "$CARGO_JOBS"
mv target/release/oxicloud /usr/bin/oxicloud && chmod +x /usr/bin/oxicloud
# Reclaim ~3 GB of build artifacts; keep source for updates.
rm -rf /opt/oxicloud/target /opt/oxicloud/frontend/node_modules
msg_ok "Built OxiCloud"

msg_info "Configuring OxiCloud"
mkdir -p {/mnt/oxicloud,/etc/oxicloud}
sed -e 's|OXICLOUD_STORAGE_PATH=.*|OXICLOUD_STORAGE_PATH=/mnt/oxicloud|' \
  -e 's|OXICLOUD_SERVER_HOST=.*|OXICLOUD_SERVER_HOST=0.0.0.0|' \
  -e 's|OXICLOUD_STATIC_PATH=.*|OXICLOUD_STATIC_PATH=/opt/oxicloud/static-dist|' \
  -e "s|^#OXICLOUD_BASE_URL=.*|OXICLOUD_BASE_URL=http://${LOCAL_IP}:8086|" \
  -e "s|OXICLOUD_DB_CONNECTION_STRING=.*|OXICLOUD_DB_CONNECTION_STRING=${DATABASE_URL}|" \
  -e "s|^DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|" \
  -e "s|^#OXICLOUD_JWT_SECRET=.*|OXICLOUD_JWT_SECRET=$(openssl rand -hex 32)|" \
  /opt/oxicloud/example.env >/etc/oxicloud/.env
chmod 600 /etc/oxicloud/.env
msg_ok "Configured OxiCloud"

msg_info "Creating OxiCloud Service"
cat <<EOF >/etc/systemd/system/oxicloud.service
[Unit]
Description=OxiCloud Service
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/oxicloud/.env
ExecStart=/usr/bin/oxicloud
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now oxicloud
msg_ok "Created OxiCloud Service"

motd_ssh
customize
cleanup_lxc
