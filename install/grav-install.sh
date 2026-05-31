#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Raffaele [rafspiny]
# License: MIT | https://github.com/rafspiny/ProxmoxVED/raw/main/LICENSE
# Source: https://getgrav.org/

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
set -x
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;logrotate;nginx)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  logrotate \
  curl
msg_ok "Installed Dependencies"

# PHP
msg_info "Setup PHP"
PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php
msg_ok "PHP installed"

# Temp

# Setup App
msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -s "https://api.github.com/repos/getgrav/grav/releases/latest" | grep '"tag_name"' | awk -F'"' '{print $4}')
curl -fsSL "https://github.com/getgrav/grav/releases/download/${RELEASE}/grav-admin-v${RELEASE}.zip" -o /tmp/grav-admin.zip
unzip -q /tmp/grav-admin.zip -d /tmp/
mv /tmp/grav-admin /opt/${APPLICATION,,}
chown -R www-data:www-data /opt/${APPLICATION,,}
find /opt/${APPLICATION,,} -type f -exec chmod 664 {} \;
find /opt/${APPLICATION,,} -type d -exec chmod 775 {} \;
find /opt/${APPLICATION,,}/bin -type f -exec chmod 775 {} \;
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

# Configuring Nginx
msg_info "Configuring Nginx"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
rm -f /etc/nginx/sites-enabled/default
cat <<EOF >/etc/nginx/sites-available/${APPLICATION,,}
server {
    listen 80;
    server_name _;
    root /opt/${APPLICATION,,};
    index index.html index.htm index.php;

    location / {
        try_files \$uri \$uri/ /index.html /index.htm /index.php\$is_args\$args;
    }

    ## Begin - Security
    location ~* /(\.git|cache|bin|logs|backup|tests)/.*$ { return 403; }
    location ~* /(system|vendor)/.*\.(txt|xml|md|html|json|yaml|yml|php|pl|py|cgi|twig|sh|bat)$ { return 403; }
    location ~* /user/.*\.(txt|md|json|yaml|yml|php|pl|py|cgi|twig|sh|bat)$ { return 403; }
    location ~ /(LICENSE\.txt|composer\.lock|composer\.json|nginx\.conf|web\.config|htaccess\.txt|\.htaccess) { return 403; }
    ## End - Security

    ## Begin - Caching
    location ~* ^/forms-basic-captcha-image.jpg$ {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~* \.(?:ico|css|js|gif|jpe?g|png)$ {
        expires 30d;
        add_header Vary Accept-Encoding;
        log_not_found off;
    }

    location ~* ^.+\.(?:css|cur|js|jpe?g|gif|htc|ico|png|html|xml|otf|ttf|eot|woff|woff2|svg)$ {
        access_log off;
        expires 30d;
        add_header Cache-Control public;
        tcp_nodelay off;
        open_file_cache max=3000 inactive=120s;
        open_file_cache_valid 45s;
        open_file_cache_min_uses 2;
        open_file_cache_errors off;
    }
    ## End - Caching

    location ~ ^(.+\.php)(.*)$ {
        fastcgi_split_path_info ^(.+\.php)(.*)$;
        if (!-f \$document_root\$fastcgi_script_name) { return 404; }
        fastcgi_pass unix:/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
ln -sf /etc/nginx/sites-available/${APPLICATION,,} /etc/nginx/sites-enabled/${APPLICATION,,}
systemctl enable -q --now php${PHP_VER}-fpm
$STD nginx -t
systemctl enable -q --now nginx
$STD nginx -s reload
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc

# Cleanup
msg_info "Cleaning up"
rm -f /tmp/grav-admin.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
