#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  gpg \
  curl \
  sudo \
  mc \
  gcc \
  libpq-dev \
  libcurl4-openssl-dev \
  libssl-dev
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
	python3 python3-dev python3-venv python3-pip
$STD pip install --upgrade pip
msg_ok "Setup Python3"
msg_info "Setting up PostgreSQL Repository"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-17
msg_ok "Set up PostgreSQL Repository"


msg_info "Setup Database"
DB_NAME=healthchecks_db
DB_USER=hc_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
SECRET_KEY="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)"

$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
    echo "healthchecks-Credentials"
    echo "healthchecks Database User: $DB_USER"
    echo "healthchecks Database Password: $DB_PASS"
    echo "healthchecks Database Name: $DB_NAME"
} >> ~/healthchecks.creds
msg_ok "Set up Database"

msg_info "Setup healthchecks"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/healthchecks/healthchecks/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/healthchecks/healthchecks/archive/refs/tags/v${RELEASE}.zip"
unzip -q v${RELEASE}.zip
mv healthchecks-${RELEASE} /opt/healthchecks
cd /opt/healthchecks
pip install --upgrade pip
pip install wheel
pip install -r requirements.txt
CAT EOF
python3 -m venv hc-venv
source hc-venv/bin/activate
pip3 install wheel
pip install -r requirements.txt
cat <<EOF >/opt/healthchecks/.env
DB=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}

# Django & Healthchecks Konfiguration
SECRET_KEY=${SECRET_KEY}
DEBUG=False
ALLOWED_HOSTS=your.domain.com
SITE_ROOT=https://your.domain.com
EOF

source /opt/healthchecks/venv/bin/activate
python3 manage.py migrate
cat <<EOF | python3 /opt/healthchecks/manage.py shell
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', password='$DB_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
./manage.py createsuperuser


msg_ok "Installed healthchecks"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/healthchecks.service
[Unit]
Description=Healthchecks Service
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/healthchecks/
ExecStart=python3 manage.py runserver 0.0.0.0:8000
Restart=always
EnvironmentFile=/opt/healthchecks/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now healthchecks
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/v${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
