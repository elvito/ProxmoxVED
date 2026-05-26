#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://waydro.id/

source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/vm-core.func")
load_functions

function header_info {
  clear
  cat <<"EOF"
 __          __             _         _     _
 \ \        / /            | |       (_)   | |
  \ \  /\  / /__ _ _  _  __| |_ __ ___  __| |
   \ \/  \/ / _` | | | |/ _` | '__/ _ \/ _` |
    \  /\  / (_| | |_| | (_| | | | (_) | (_| |
     \/  \/ \__,_|\__, |\__,_|_|  \___/ \__,_|
                   __/ |
                  |___/   Android Container on Linux
EOF
}

APP="Waydroid VM"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="waydroid-vm"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"
SNIPPETS_STOR=""
SNIPPETS_DIR=""

# OS selection defaults
OS_CHOICE="ubuntu2404"
OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
WAYDROID_DISTRO="noble"

header_info
echo -e "\n Loading..."

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if vm_confirm_new_vm "$APP" "This will create a New $APP. Proceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

# ---------------------------------------------------------------------------
# OS Selection
# ---------------------------------------------------------------------------
function prompt_os_choice() {
  local choice
  if choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "OS SELECTION" \
    --radiolist "Choose the base operating system:" --cancel-button Exit-Script 12 68 2 \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble Numbat)" ON \
    "debian13" "Debian 13 (Trixie)" OFF \
    3>&1 1>&2 2>&3); then
    OS_CHOICE="$choice"
    case "$OS_CHOICE" in
    ubuntu2404)
      OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
      WAYDROID_DISTRO="noble"
      ;;
    debian13)
      OS_LABEL="Debian 13 (Trixie)"
      WAYDROID_DISTRO="trixie"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Base OS: ${BGN}${OS_LABEL}${CL}"
  else
    exit_script
  fi
}

prompt_os_choice
vm_prompt_cloud_init "ubuntu"

# ---------------------------------------------------------------------------
# Find snippets-capable storage for cicustom vendor-data
# ---------------------------------------------------------------------------
function find_snippets_storage() {
  local stor path
  stor=$(awk '
    /^dir:/ { cur=$2 }
    /^nfs:/ { cur=$2 }
    /^btrfs:/ { cur=$2 }
    cur && /content/ && /snippets/ { print cur; exit }
  ' /etc/pve/storage.cfg 2>/dev/null)
  [[ -z "$stor" ]] && return 1

  path=$(awk -v s="$stor" '
    $0 ~ "^(dir|nfs|btrfs): " s { found=1; next }
    found && /^\tpath/ { print $2; exit }
    found && /^[a-z]/ { exit }
  ' /etc/pve/storage.cfg 2>/dev/null)
  path="${path:-/var/lib/vz}"

  SNIPPETS_STOR="$stor"
  SNIPPETS_DIR="${path}/snippets"
  mkdir -p "$SNIPPETS_DIR"
  return 0
}

# ---------------------------------------------------------------------------
# Write cloud-init vendor-data snippet for Waydroid installation
# ---------------------------------------------------------------------------
function write_waydroid_vendor_data() {
  local distro="$1"
  cat >"${SNIPPETS_DIR}/waydroid-${VMID}-vendor.yaml" <<EOF
#cloud-config
runcmd:
  - modprobe binder_linux devices=binder,hwbinder,vndbinder
  - echo 'binder_linux' | tee -a /etc/modules
  - curl -fsSL https://repo.waydro.id | bash -s ${distro}
  - apt-get install -y waydroid
  - systemctl enable --now waydroid-container
EOF
}

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="20G"
  DISK_CACHE=""
  HN="waydroid"
  CPU_TYPE=""
  CORE_COUNT="4"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Waydroid VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${DISK_SIZE:-20G}" "Set Disk Size in GiB (min. 20 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "waydroid"
  vm_prompt_cpu_model "kvm64"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${OS_LABEL} Waydroid VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Waydroid VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if vm_choose_settings_mode; then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

start_script
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2
DISK_IMPORT="-format ${DISK_IMPORT_FORMAT}"

# ---------------------------------------------------------------------------
# Download cloud image based on selected OS
# ---------------------------------------------------------------------------
case "$OS_CHOICE" in
ubuntu2404)
  msg_info "Retrieving the URL for the Ubuntu 24.04 Cloud Image"
  URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  ;;
debian13)
  msg_info "Retrieving the URL for the Debian 13 Cloud Image"
  URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
  ;;
esac
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE="$(basename "$URL")"
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

msg_info "Creating a ${OS_LABEL} Waydroid VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,waydroid -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID $FILE $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
set_description

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f setup_cloud_init >/dev/null 2>&1; then
  case "$OS_CHOICE" in
  ubuntu2404) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-ubuntu}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  debian13) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-debian}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  esac
else
  # Even without interactive cloud-init config, attach a CI drive for network (DHCP)
  qm set $VMID --ide2 "${STORAGE}:cloudinit" >/dev/null 2>&1 ||
    qm set $VMID --scsi1 "${STORAGE}:cloudinit" >/dev/null 2>&1 || true
  qm set $VMID --ipconfig0 "ip=dhcp" >/dev/null 2>&1 || true
fi

# Inject Waydroid auto-install via cicustom vendor-data (runs on first boot)
msg_info "Setting up Waydroid auto-install via cloud-init"
if find_snippets_storage; then
  write_waydroid_vendor_data "$WAYDROID_DISTRO"
  qm set $VMID --cicustom "vendor=${SNIPPETS_STOR}:snippets/waydroid-${VMID}-vendor.yaml" >/dev/null
  qm cloudinit update $VMID >/dev/null 2>&1 || true
  msg_ok "Waydroid will be installed automatically on first boot"
else
  msg_warn "No snippets-capable storage found — Waydroid must be installed manually after boot"
fi

msg_ok "Created a ${OS_LABEL} Waydroid VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Waydroid VM"
  qm start $VMID
  msg_ok "Started Waydroid VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

if [[ -n "$SNIPPETS_STOR" ]]; then
  cat <<INSTRUCTIONS

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    WAYDROID AUTO-INSTALL ACTIVE                         │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  Waydroid will be installed automatically on first boot via cloud-init. │
  │  This takes a few minutes. Check progress inside the VM with:           │
  │       sudo cloud-init status --wait                                     │
  │       sudo journalctl -u cloud-init -f                                  │
  │                                                                         │
  │  After cloud-init finishes, initialize Waydroid (once, as root):        │
  │       sudo waydroid init                                                 │
  │       sudo systemctl start waydroid-container                           │
  │                                                                         │
  │  NOTE: GPU acceleration requires VirtIO GPU or passthrough setup.       │
  │  More info: https://docs.waydro.id/                                     │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS
else
  cat <<INSTRUCTIONS

  ┌─────────────────────────────────────────────────────────────────────────┐
  │              WAYDROID MANUAL POST-INSTALL STEPS                         │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  No snippets storage found. After the VM has booted, run manually:      │
  │                                                                         │
  │  1. Load binder kernel module:                                          │
  │       sudo modprobe binder_linux devices=binder,hwbinder,vndbinder      │
  │       echo 'binder_linux' | sudo tee -a /etc/modules                   │
  │                                                                         │
  │  2. Install Waydroid:                                                   │
  │       curl -s https://repo.waydro.id | sudo bash                       │
  │       sudo apt install -y waydroid                                      │
  │                                                                         │
  │  3. Initialize Waydroid (requires internet):                            │
  │       sudo waydroid init                                                │
  │       sudo systemctl start waydroid-container                           │
  │                                                                         │
  │  NOTE: GPU acceleration requires VirtIO GPU or passthrough setup.       │
  │  More info: https://docs.waydro.id/                                     │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS
fi

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
fi
