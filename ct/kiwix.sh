#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s kiwix-tools &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(cat /root/.kiwix 2>/dev/null || dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')

  msg_info "Stopping Service"
  systemctl stop kiwix-serve
  msg_ok "Stopped Service"

  msg_info "Updating Kiwix-Tools"
  $STD apt update
  $STD apt install -y --only-upgrade kiwix-tools
  RELEASE=$(dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')
  echo "${RELEASE}" >/root/.kiwix
  msg_ok "Updated Kiwix-Tools"

  if [[ "$CURRENT" == "$RELEASE" ]]; then
    msg_ok "Already on latest version: ${CURRENT}"
  else
    msg_ok "Updated successfully from ${CURRENT} to ${RELEASE}!"
  fi

  msg_info "Starting Service"
  systemctl start kiwix-serve
  msg_ok "Started Service"
  exit
}

start
build_container

msg_info "Validating ZIM directory."
if [[ -z "${ZIM_DATA:-}" ]]; then
  msg_error "ZIM_DATA cannot be empty. Please run with ZIM_DATA=/path/to/zims"
  exit 1
fi
if [[ ! -d "$ZIM_DATA" ]]; then
  msg_error "Directory '$ZIM_DATA' does not exist."
  exit 1
fi
if ! ls "${ZIM_DATA}"/*.zim >/dev/null 2>&1; then
  msg_error "No .zim files found in '$ZIM_DATA'"
  exit 1
fi
msg_ok "Using ZIM directory: ${ZIM_DATA}"

msg_info "Configuring Bind Mount"

if pct set $CTID -features mountidmap=1 2>/dev/null; then
  msg_info "Enabled ID-mapped mounts (ownership preserved)"
  pct set $CTID -mp0 "$ZIM_DATA,mp=/data,ro=1"
  msg_ok "Bind Mount Configured (read-only, ownership preserved)"
else
  msg_info "ID-mapped mounts not available, using standard mount"
  msg_info "Note: Files will appear as nobody:nogroup inside container"
  msg_info "Ensure ZIM files are world-readable: chmod -R a+rX ${ZIM_DATA}"
  pct set $CTID -mp0 "$ZIM_DATA,mp=/data"
  msg_ok "Bind Mount Configured (read-write mount, read-only service)"
fi

msg_info "Starting Service"
pct exec $CTID -- systemctl start kiwix-serve
msg_ok "Started Service"

msg_info "Setting Container Options"
pct set $CTID --onboot 1
msg_ok "Container Options Set"

msg_ok "Completed Successfully!\n"
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo -e "${TAB}${GATEWAY}${BGN}Web Interface:${CL} ${BL}http://${IP}:8080${CL}"
echo -e "${TAB}${INFO}${BGN}ZIM Directory:${CL} ${ZIM_DATA} ${DGN}→${CL} ${BGN}/data${CL}"
