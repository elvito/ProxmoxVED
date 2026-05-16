#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ProxmoxVED Community
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://aliasvault.net

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  >/etc/apt/sources.list.d/docker.list
$STD apt update
$STD apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable -q --now docker
msg_ok "Installed Docker"

RELEASE=$(get_latest_github_release "aliasvault/aliasvault")
msg_info "Setting up AliasVault ${RELEASE}"
mkdir -p /opt/aliasvault/{database/postgres,logs/msbuild,secrets,certificates/{ssl,smtp,letsencrypt/www}}
curl -fsSL "https://raw.githubusercontent.com/aliasvault/aliasvault/${RELEASE}/docker-compose.yml" |
  sed "s/:latest/:${RELEASE}/g" >/opt/aliasvault/docker-compose.yml
curl -fsSL "https://raw.githubusercontent.com/aliasvault/aliasvault/${RELEASE}/docker-compose.letsencrypt.yml" \
  >/opt/aliasvault/docker-compose.letsencrypt.yml
msg_ok "Set up AliasVault ${RELEASE}"

msg_info "Generating Secrets"
chmod 700 /opt/aliasvault/secrets
printf '%s' "$(openssl rand -base64 32)" >/opt/aliasvault/secrets/jwt_key
printf '%s' "$(openssl rand -base64 32)" >/opt/aliasvault/secrets/data_protection_cert_pass
printf '%s' "$(openssl rand -base64 32)" >/opt/aliasvault/secrets/postgres_password
ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
ADMIN_HASH=$(docker run --rm ghcr.io/aliasvault/installcli:latest hash-password "$ADMIN_PASS")
printf '%s' "${ADMIN_HASH}|$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >/opt/aliasvault/secrets/admin_password_hash
chmod 600 /opt/aliasvault/secrets/*
msg_ok "Generated Secrets"

msg_info "Creating Configuration"
cat <<EOF >/opt/aliasvault/.env
HTTP_PORT=80
HTTPS_PORT=443
SMTP_PORT=25
SMTP_TLS_PORT=587
FORCE_HTTPS_REDIRECT=true
PRIVATE_EMAIL_DOMAINS=
HIDDEN_PRIVATE_EMAIL_DOMAINS=
SMTP_ADVERTISED_HOSTNAME=
SMTP_TLS_ENABLED=false
LETSENCRYPT_ENABLED=false
HOSTNAME=localhost
PUBLIC_REGISTRATION_ENABLED=true
IP_LOGGING_ENABLED=true
SUPPORT_EMAIL=
MAX_UPLOAD_SIZE_MB=100
ADMIN_IP_ALLOWLIST=
TRUSTED_PROXIES=
DEPLOYMENT_MODE=install
ALIASVAULT_VERSION=${RELEASE}
EOF
msg_ok "Created Configuration"

msg_info "Starting Services"
cd /opt/aliasvault
$STD docker compose up -d
echo "${RELEASE}" >~/.aliasvault
msg_ok "Started Services"

echo ""
echo "================================================================"
echo "  AliasVault Initial Admin Credentials"
echo "  Username: admin"
echo "  Password: ${ADMIN_PASS}"
echo "  Save these credentials — they will not be shown again!"
echo "================================================================"
echo ""

motd_ssh
customize
cleanup_lxc
