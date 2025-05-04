#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/opf/openproject

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    lsb-release \
    ca-certificates \
    acl \
    fping \
    graphviz \
    imagemagick \
    mariadb-client \
    mariadb-server \
    mtr-tiny \
    nginx \
    nmap \
    rrdtool \
    snmp \
    snmpd \
    git \
    whois
msg_ok "Installed Dependencies"

msg_info "Installing PHP"
$STD apt-get install -y \
    php8.2-{cli,fpm,gd,gmp,mbstring,mysql,snmp,xml,zip,curl}
msg_ok "Installed PHP"

msg_info "Installing Python"
$STD apt-get install -y \
    python3-{dotenv,pymysql,redis,setuptools,systemd,pip}
msg_ok "Installed Python"

msg_info "Add User"
$STD useradd librenms -d /opt/librenms -M -r -s "$(which bash)"
msg_ok "Add User"

msg_info "Configuring Database"
DB_NAME=librenms
DB_USER=librenms
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mariadb -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
    echo "LibreNMS-Credentials"
    echo "LibreNMS Database User: $DB_USER"
    echo "LibreNMS Database Password: $DB_PASS"
    echo "LibreNMS Database Name: $DB_NAME"
} >>~/librenms.creds
msg_ok "Configured Database"

msg_info "Setup Librenms"
tmp_file=$(mktemp)
RELEASE=$(curl -fsSL https://api.github.com/repos/librenms/librenms/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL https://github.com/librenms/librenms/archive/refs/tags/${RELEASE}.tar.gz -o $tmp_file
tar -xzf $tmp_file -C /opt
mv /opt/librenms-${RELEASE} /opt/librenms
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
msg_ok "Setup Librenms"

msg_info "Setup Composer"
cd /opt
curl -fsSL https://getcomposer.org/composer-stable.phar -o /usr/bin/composer
chmod +x /usr/bin/composer
cd /opt/librenms
$STD composer install --no-dev -o --no-interaction
chown -R librenms:librenms /opt/librenms
chmod 771 /opt/librenms
setfacl -d -m g::rwx /opt/librenms/bootstrap/cache /opt/librenms/storage /opt/librenms/logs /opt/librenms/rrd
chmod -R ug=rwX /opt/librenms/bootstrap/cache /opt/librenms/storage /opt/librenms/logs /opt/librenms/rrd
msg_ok "Setup Composer"

msg_info "Setup PHP"
sed -i 's/;date.timezone =/date.timezone = UTC/' /etc/php/8.2/cli/php.ini
sed -i 's/;date.timezone =/date.timezone = UTC/' /etc/php/8.2/fpm/php.ini
msg_ok "Setup PHP"

msg_info "Setup MariaDB"
sed -i '/\[mysqld\]/a innodb_file_per_table=1\nlower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl enable -q --now mariadb
msg_ok "Setup MariaDB"

msg_info "Configure PHP-FPM"
cp /etc/php/8.2/fpm/pool.d/www.conf /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/\[www\]/\[librenms\]/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/user = www-data/user = librenms/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/group = www-data/group = librenms/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/listen = \/run\/php\/php8.2-fpm.sock/listen = \/run\/php-fpm-librenms.sock/g" /etc/php/8.2/fpm/pool.d/librenms.conf
msg_ok "Configured PHP-FPM"

msg_info "Configure Nginx"
IP_ADDR=$(hostname -I | awk '{print $1}')
cat >/etc/nginx/sites-enabled/librenms <<'EOF'
server {
 listen      80;
 server_name ${IP_ADDR};
 root        /opt/librenms/html;
 index       index.php;

 charset utf-8;
 gzip on;
 gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
 location / {
  try_files $uri $uri/ /index.php?$query_string;
 }
 location ~ [^/]\.php(/|$) {
  fastcgi_pass unix:/run/php-fpm-librenms.sock;
  fastcgi_split_path_info ^(.+\.php)(/.+)$;
  include fastcgi.conf;
 }
 location ~ /\.(?!well-known).* {
  deny all;
 }
}
EOF
rm /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
systemctl restart php8.2-fpm
msg_ok "Configured Nginx"

msg_info "Configure Services"
ln -s /opt/librenms/lnms /usr/bin/lnms
mkdir -p /etc/bash_completion.d/
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf

RANDOM_STRING=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
sed -i "s/RANDOMSTRINGHERE/$RANDOM_STRING/g" /etc/snmp/snmpd.conf
echo "SNMP Community String: $RANDOM_STRING" >>~/librenms.creds
curl -qo /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable -q --now snmpd

cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms
cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/

systemctl enable -q --now librenms-scheduler.timer
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
msg_ok "Configured Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $tmp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
