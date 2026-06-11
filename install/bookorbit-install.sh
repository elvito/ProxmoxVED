#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bookorbit/bookorbit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  ffmpeg \
  poppler-utils \
  python3-venv
msg_ok "Installed Dependencies"

PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="bookorbit" PG_DB_USER="bookorbit" PG_DB_EXTENSIONS="uuid-ossp,pg_trgm,vector" setup_postgresql_db
NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball" "latest" "/opt/bookorbit-src"

msg_info "Building Application"
cd /opt/bookorbit-src
$STD corepack enable
$STD corepack prepare pnpm@10.32.1 --activate
$STD pnpm install --frozen-lockfile
$STD pnpm --filter client run build-only
$STD pnpm --filter server run build
rm -rf /opt/bookorbit-deploy
$STD pnpm --filter server deploy --prod --legacy /opt/bookorbit-deploy
cp -r /opt/bookorbit-src/server/dist /opt/bookorbit-deploy/dist
mkdir -p /opt/bookorbit-deploy/migrations
cp -r /opt/bookorbit-src/server/src/db/migrations/. /opt/bookorbit-deploy/migrations/
cp -r /opt/bookorbit-src/client/dist /opt/bookorbit-deploy/public
cp /opt/bookorbit-src/server/entrypoint.sh /opt/bookorbit-deploy/entrypoint.sh
mkdir -p /opt/bookorbit-deploy/bin/kepubify
cp -r /opt/bookorbit-src/server/bin/kepubify/. /opt/bookorbit-deploy/bin/kepubify/
chmod +x /opt/bookorbit-deploy/entrypoint.sh /opt/bookorbit-deploy/bin/kepubify/*
rm -rf /opt/bookorbit
mv /opt/bookorbit-deploy /opt/bookorbit
msg_ok "Built Application"

msg_info "Setting up Python Runtime"
python3 -m venv /opt/bookorbit-python
/opt/bookorbit-python/bin/python -m pip install --upgrade pip
/opt/bookorbit-python/bin/python -m pip install --no-cache-dir -r /opt/bookorbit-src/server/requirements/kobo-cloudscraper.txt
msg_ok "Set up Python Runtime"

msg_info "Configuring Application"
mkdir -p /opt/bookorbit-data/covers /opt/bookorbit-data/book-bucket /opt/bookorbit-books
JWT_SECRET=$(openssl rand -hex 32)
SETUP_BOOTSTRAP_TOKEN=$(openssl rand -hex 16)
cat <<EOF >/opt/bookorbit/.env
NODE_ENV=production
PORT=3000
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_USER=${PG_DB_USER}
POSTGRES_PASSWORD=${PG_DB_PASS}
POSTGRES_DB=${PG_DB_NAME}
JWT_SECRET=${JWT_SECRET}
SETUP_BOOTSTRAP_TOKEN=${SETUP_BOOTSTRAP_TOKEN}
APP_URL=http://${LOCAL_IP}:3000
CLIENT_URL=http://${LOCAL_IP}:3000
PUID=0
PGID=0
NODE_MAX_OLD_SPACE_SIZE=2048
APP_DATA_PATH=/opt/bookorbit-data
KOBO_CLOUDSCRAPER_PYTHON=/opt/bookorbit-python/bin/python
BOOK_DOCK_PATH=/opt/bookorbit-data/book-bucket
EOF
msg_ok "Configured Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bookorbit.service
[Unit]
Description=BookOrbit Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bookorbit
EnvironmentFile=/opt/bookorbit/.env
ExecStart=/usr/bin/env sh /opt/bookorbit/entrypoint.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bookorbit
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
