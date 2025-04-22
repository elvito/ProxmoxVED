#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PCJones/MediathekArr

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o packages-microsoft-prod.deb
$STD dpkg -i packages-microsoft-prod.deb
$STD apt-get update
$STD apt-get install -y \
  dotnet-sdk-9.0 \
  mkvtoolnix
  msg_ok "Installed Dependencies"

msg_info "Installing MediathekArr"
temp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/PCJones/MediathekArr/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
curl -fsSL "https://github.com/PCJones/MediathekArr/archive/refs/tags/${RELEASE}.zip" -o $temp_file
unzip -qu $temp_file '*/**' -d /opt/MediathekArr
echo "${RELEASE}" >"/opt/Mediathekarr_version.txt"
cd /opt/MediathekArr
dotnet restore
dotnet build
cp .env.example .env
msg_ok "Installation completed"

msg_info "Creating appsettings.json"
cat <<EOF >/opt/MediathekArr/appsettings.json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://0.0.0.0:5007"
      }
    }
  },
  "AppSettings": {
    "BaseUrl": "http://localhost:5007",
    "MaxConcurrentDownloads": 3,
    "MediaPath": "/path/to/media/directory"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "Radarr": {
    "ApiUrl": "http://localhost:7878/api",
    "ApiKey": "<DEIN_RADARR_API_KEY>"
  },
  "Sonarr": {
    "ApiUrl": "http://localhost:8989/api",
    "ApiKey": "<DEIN_SONARR_API_KEY>"
  },
  "Lidarr": {
    "ApiUrl": "http://localhost:8686/api",
    "ApiKey": "<DEIN_LIDARR_API_KEY>"
  },
  "Database": {
    "ConnectionString": "Server=localhost;Database=mediathekarr;User Id=admin;Password=yourpassword;"
  },
  "ExternalServices": {
    "NotifyServiceUrl": "http://localhost:5001/notify",
    "NotifyServiceKey": "<DEIN_NOTIFY_SERVICE_KEY>"
  }
}
EOF
msg_ok "appsettings.json created"

msg_info "Creating systemd Services"
cat <<EOF >/etc/systemd/system/mediathekarrserver.service
[Unit]
Description=MediathekArr Server Service
After=network.target

[Service]
WorkingDirectory=/opt/MediathekArr
ExecStart=/usr/bin/dotnet run --project MediathekArrServer
Restart=always
RestartSec=10
SyslogIdentifier=mediathekarrserver
User=root
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/mediathekarr.service
[Unit]
Description=MediathekArr Service
After=network.target

[Service]
WorkingDirectory=/opt/MediathekArr
ExecStart=/usr/bin/dotnet run --no-launch-profile --project MediathekArr
Restart=always
RestartSec=10
SyslogIdentifier=mediathekarr
User=root
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF
systemctl -q --now enable mediathekarrserver
systemctl -q --now enable mediathekarr
msg_ok "Created and started systemd Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $temp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
