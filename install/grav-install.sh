#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Raffaele [rafspiny]
# License: MIT | https://github.com/rafspiny/ProxmoxVED/raw/main/LICENSE
# Source: https://getgrav.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;logrotate;nginx)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  logrotate
msg_ok "Installed Dependencies"

PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php

msg_info "Setup Grav"
fetch_and_deploy_gh_release "grav" "getgrav/grav" "prebuild" "latest" "/opt/grav" "grav-admin-v*zip"
chown -R www-data:www-data /opt/${APPLICATION,,}
msg_ok "Setup Grav"

msg_info "Configuring Nginx"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
unlink /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
cat <<EOF >/etc/nginx/sites-available/grav
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
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
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
