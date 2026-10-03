#!/bin/bash
#
# Create a Proxmox VE VM from a cloud image, configured through the native
# Proxmox cloud-init drive (user, password, SSH keys, network) plus a vendor
# snippet (timezone, packages, commands).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set colors
GN='\033[0;32m'
YL='\033[1;33m'
BL='\033[0;34m'
NC='\033[0m' # No Color (reset)

# Defaults (override in pve-cloud-init.conf or with options)
SNIPPET_STORAGE="local"
IMAGE_DIR="/var/lib/vz/template/iso"
BRIDGE="vmbr0"
NAMESERVER="1.1.1.1 8.8.8.8"
SEARCHDOMAIN=""
SEARCHDOMAIN_GIVEN=false
TIMEZONE="America/New_York"
SSH_KEYS_FILE=""
VLAN=""
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/pve-cloud-init.conf" ]] && source "$SCRIPT_DIR/pve-cloud-init.conf"

DISTRIBUTION="" STORAGE="" VM_ID="" VM_NAME="" CPU_TYPE="" CPU_CORES=""
MEMORY="" DISK_SIZE="" SECOND_DISK="" DISK2_SIZE="" VM_IP="" GATEWAY=""
CINIT_USER=""
CINIT_PASSWORD="${CINIT_PASSWORD:-}"   # may be supplied via the environment
SNIPPET_FILE=""
VM_CREATED=false

die() {
    echo -e "${YL}Error:${NC} $*" >&2
    exit 1
}

read_colored() {
    local prompt="$1"
    local var_name="$2"
    echo -n "$prompt"
    echo -ne "$GN"
    read -r "$var_name" || { echo -e "${NC}\n${YL}Input closed; run from an interactive terminal (ssh -t).${NC}" >&2; exit 1; }
    echo -ne "$NC"
}

# Remove a half-built VM and its snippet if anything fails
cleanup() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        if [[ "$VM_CREATED" == true ]]; then
            echo -e "\n${YL}Failed. Removing partially created VM ${VM_ID}.${NC}" >&2
            qm destroy "$VM_ID" --purge 1> /dev/null 2>&1 || true
        fi
        [[ -n "$SNIPPET_FILE" ]] && rm -f "$SNIPPET_FILE"
    fi
}
trap cleanup EXIT

need_arg() {
    [[ $# -ge 2 ]] || die "Option $1 requires a value"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates a VM from a cloud image using the Proxmox cloud-init drive.
Missing values are prompted for.

OPTIONS:
    --distro DISTRIBUTION          ubuntu, debian, alma, centos, fedora
    -s, --storage STORAGE          Storage for VM disks (menu shown if invalid)
    -i, --id VM_ID                 VM ID number
    -n, --name VM_NAME             VM hostname
    -t, --cpu-type CPU_TYPE        CPU type (default: x86-64-v3)
    -c, --cpu-cores CPU_CORES      CPU cores (default: 2)
    -m, --memory MEMORY            RAM in MB (default: 4096)
    -d, --disk-size DISK_SIZE      Primary disk size in GB (default: 20)
    -a, --ip IP_ADDRESS[/PREFIX]   VM IP address (default prefix: /24)
    -g, --gateway GATEWAY          Default gateway (default: x.x.x.1)
    --search-domain DOMAINS        DNS search domains, space or comma separated
    -b, --bridge BRIDGE            Network bridge (default: vmbr0)
    -v, --vlan VLAN_ID             VLAN tag for the VM's NIC (default: untagged)
    -u, --user USERNAME            Cloud-init username
    --second-disk yes|no           Whether to add a second disk
    -2, --disk2-size DISK2_SIZE    Second disk size in GB (implies yes)
    -h, --help                     Show this help message

The user's password is always prompted for (or read from \$CINIT_PASSWORD).
Defaults for DNS, timezone, SSH keys, etc. live in pve-cloud-init.conf.

EXAMPLES:
    $0

    $0 --distro alma --storage crucial --id 149 --name test149 \\
       --cpu-type x86-64-v3 --cpu-cores 2 --memory 6144 --disk-size 30 \\
       --ip 192.168.1.149 --gateway 192.168.1.1 --user john --disk2-size 30
EOF
}

# Print a numbered menu of $@ and set REPLY_CHOICE to the selected item
choose_from_list() {
    local -a items=("$@")
    local i choice
    for i in "${!items[@]}"; do
        echo "  $((i + 1))) ${items[$i]}"
    done
    echo ""
    while true; do
        read_colored "Enter selection (1-${#items[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
            REPLY_CHOICE="${items[$((choice - 1))]}"
            return
        fi
        echo -e "${YL}Invalid selection.${NC}"
    done
}

select_storage() {
    local -a available
    mapfile -t available < <(pvesm status --content images 2> /dev/null | awk 'NR>1 && $3=="active" {print $1}')
    [[ ${#available[@]} -gt 0 ]] || die "No storage that can hold VM images was found"

    local s
    for s in "${available[@]}"; do
        [[ -n "$STORAGE" && "$s" == "$STORAGE" ]] && return
    done

    if [[ -n "$STORAGE" ]]; then
        echo -e "${YL}Storage '${STORAGE}' does not exist or cannot hold VM images.${NC}\n"
    fi
    echo -e "${BL}Select a storage location:${NC}\n"
    choose_from_list "${available[@]}"
    STORAGE="$REPLY_CHOICE"
    echo ""
}

select_distribution() {
    local distro_choice="" use_param=false

    case "${DISTRIBUTION,,}" in
        "") ;;
        ubuntu) distro_choice=1; use_param=true ;;
        debian) distro_choice=2; use_param=true ;;
        alma) distro_choice=3; use_param=true ;;
        centos) distro_choice=4; use_param=true ;;
        fedora) distro_choice=5; use_param=true ;;
        *)
            echo -e "${YL}Warning: Invalid distribution '${DISTRIBUTION}' provided.${NC}"
            echo -e "${YL}Valid options are: ubuntu, debian, alma, centos, fedora${NC}\n"
            ;;
    esac

    if [[ "$use_param" == false ]]; then
        echo -e "${BL}Select a Linux distribution:${NC}\n"
        echo "  1) Ubuntu 26.04 LTS"
        echo "  2) Debian 13"
        echo "  3) Alma Linux 10"
        echo "  4) CentOS Stream 10"
        echo "  5) Fedora 43"
        echo ""
        read_colored "Enter selection (1-5): " distro_choice
        echo ""
    fi

    case $distro_choice in
        1)
            DISTRO_NAME="Ubuntu 26.04 LTS"
            IMAGE_FILENAME="$IMAGE_DIR/ubuntu-2604.img"
            DOWNLOAD_URL="https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
            DISTRO_FAMILY="debian"
            ;;
        2)
            DISTRO_NAME="Debian 13"
            IMAGE_FILENAME="$IMAGE_DIR/debian-13.img"
            DOWNLOAD_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
            DISTRO_FAMILY="debian"
            ;;
        3)
            DISTRO_NAME="Alma Linux 10"
            IMAGE_FILENAME="$IMAGE_DIR/almalinux-10.img"
            DOWNLOAD_URL="https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        4)
            DISTRO_NAME="CentOS Stream 10"
            IMAGE_FILENAME="$IMAGE_DIR/centos-10.img"
            DOWNLOAD_URL="https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        5)
            DISTRO_NAME="Fedora 43"
            IMAGE_FILENAME="$IMAGE_DIR/fedora-43.img"
            DOWNLOAD_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        *)
            die "Invalid selection. Please run the script again and choose 1-5."
            ;;
    esac

    if [[ "$use_param" == true ]]; then
        echo -e "Using distribution from parameter: ${GN}${DISTRO_NAME}${NC}\n"
    else
        echo -e "Selected: ${GN}${DISTRO_NAME}${NC}\n"
    fi
}

prompt_password() {
    local pw1 pw2
    if [[ -n "$CINIT_PASSWORD" ]]; then
        return
    fi
    while true; do
        echo -n "Password for ${CINIT_USER}: "
        read -rs pw1; echo
        echo -n "Confirm password: "
        read -rs pw2; echo
        if [[ -z "$pw1" ]]; then
            echo -e "${YL}Password cannot be empty.${NC}"
        elif [[ "$pw1" != "$pw2" ]]; then
            echo -e "${YL}Passwords do not match.${NC}"
        else
            CINIT_PASSWORD="$pw1"
            return
        fi
    done
}

# ---------------------------------------------------------------- arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --distro)          need_arg "$@"; DISTRIBUTION="$2"; shift 2 ;;
        -s|--storage)      need_arg "$@"; STORAGE="$2"; shift 2 ;;
        -i|--id)           need_arg "$@"; VM_ID="$2"; shift 2 ;;
        -n|--name)         need_arg "$@"; VM_NAME="$2"; shift 2 ;;
        -t|--cpu-type)     need_arg "$@"; CPU_TYPE="$2"; shift 2 ;;
        -c|--cpu-cores)    need_arg "$@"; CPU_CORES="$2"; shift 2 ;;
        -m|--memory)       need_arg "$@"; MEMORY="$2"; shift 2 ;;
        -d|--disk-size)    need_arg "$@"; DISK_SIZE="$2"; shift 2 ;;
        --second-disk)     need_arg "$@"; SECOND_DISK="$2"; shift 2 ;;
        -a|--ip)           need_arg "$@"; VM_IP="$2"; shift 2 ;;
        -g|--gateway)      need_arg "$@"; GATEWAY="$2"; shift 2 ;;
        --search-domain)   need_arg "$@"; SEARCHDOMAIN="$2"; SEARCHDOMAIN_GIVEN=true; shift 2 ;;
        -b|--bridge)       need_arg "$@"; BRIDGE="$2"; shift 2 ;;
        -v|--vlan)         need_arg "$@"; VLAN="$2"; shift 2 ;;
        -u|--user)         need_arg "$@"; CINIT_USER="$2"; shift 2 ;;
        -2|--disk2-size)   need_arg "$@"; DISK2_SIZE="$2"; shift 2 ;;
        -h|--help)         show_usage; exit 0 ;;
        *)
            echo -e "${YL}Unknown option:${NC} $1"
            show_usage
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------ prerequisites
[[ $EUID -eq 0 ]] || die "This script must be run as root on a Proxmox VE node"
for cmd in qm pvesm openssl wget qemu-img; do
    command -v "$cmd" > /dev/null 2>&1 || die "'${cmd}' not found. Please install it and try again."
done

echo -e "\nThis script will create a VM using a cloud image and the Proxmox cloud-init drive.\n"

select_distribution
select_storage

# Snippets are needed for the vendor-data file
snippet_dir="$(pvesm path "${SNIPPET_STORAGE}:snippets/x.yaml" 2> /dev/null || true)"
if ! pvesm status --content snippets | awk 'NR>1 {print $1}' | grep -qx "$SNIPPET_STORAGE" \
   || [[ -z "$snippet_dir" ]]; then
    die "Storage '${SNIPPET_STORAGE}' does not allow snippets. Enable the 'Snippets' content type
  under Datacenter > Storage, or run: pvesm set ${SNIPPET_STORAGE} --content <existing types>,snippets"
fi
snippet_dir="$(dirname "$snippet_dir")"

# ------------------------------------------------------------------ prompts
[[ -n "$VM_ID" ]]      || read_colored "VM ID: " VM_ID
[[ -n "$VM_NAME" ]]    || read_colored "VM name: " VM_NAME
[[ -n "$CPU_TYPE" ]]   || read_colored "VM CPU type (default is x86-64-v3): " CPU_TYPE
[[ -n "$CPU_CORES" ]]  || read_colored "VM CPU cores (default is 2): " CPU_CORES
[[ -n "$MEMORY" ]]     || read_colored "VM RAM amount in MB (default is 4096): " MEMORY
[[ -n "$DISK_SIZE" ]]  || read_colored "VM disk size in GB (default is 20): " DISK_SIZE
[[ -n "$VM_IP" ]]      || read_colored "VM IP address (optionally with /prefix, default /24): " VM_IP

if [[ -z "$GATEWAY" ]]; then
    default_gw="${VM_IP%%/*}"
    default_gw="${default_gw%.*}.1"
    read_colored "Gateway (default is ${default_gw}): " GATEWAY
    GATEWAY="${GATEWAY:-$default_gw}"
fi

if [[ "$SEARCHDOMAIN_GIVEN" == false ]]; then
    default_sd="${SEARCHDOMAIN:-none}"
    read_colored "DNS search domains, space separated (default is ${default_sd}; 'none' for none): " answer
    SEARCHDOMAIN="${answer:-$SEARCHDOMAIN}"
fi
[[ "${SEARCHDOMAIN,,}" != "none" ]] || SEARCHDOMAIN=""
SEARCHDOMAIN="${SEARCHDOMAIN//,/ }"

[[ -n "$CINIT_USER" ]] || read_colored "cloud-init username (example, john): " CINIT_USER

[[ -z "$DISK2_SIZE" ]] || SECOND_DISK="yes"
[[ -n "$SECOND_DISK" ]] || read_colored "Do you want a second disk? (yes/no, default is no): " SECOND_DISK
case "${SECOND_DISK,,}" in
    y|yes) SECOND_DISK="yes" ;;
    *)     SECOND_DISK="no"; DISK2_SIZE="" ;;
esac
if [[ "$SECOND_DISK" == "yes" && -z "$DISK2_SIZE" ]]; then
    read_colored "Second disk size in GB (default is 30): " DISK2_SIZE
    DISK2_SIZE="${DISK2_SIZE:-30}"
fi

prompt_password
echo ""

# ----------------------------------------------------------- defaults/checks
CPU_TYPE="${CPU_TYPE:-x86-64-v3}"
CPU_CORES="${CPU_CORES:-2}"
MEMORY="${MEMORY:-4096}"
DISK_SIZE="${DISK_SIZE:-20}"
MEMORY="${MEMORY//[!0-9]/}"
DISK_SIZE="${DISK_SIZE//[!0-9]/}"
DISK2_SIZE="${DISK2_SIZE//[!0-9]/}"
[[ "$VM_IP" == */* ]] || VM_IP="${VM_IP}/24"

[[ "$VM_ID" =~ ^[0-9]+$ && "$VM_ID" -ge 100 ]] || die "VM ID must be a number >= 100"
qm status "$VM_ID" > /dev/null 2>&1 && die "VM ID ${VM_ID} is already in use"
[[ "$VM_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "Invalid hostname '${VM_NAME}'"
[[ "$VM_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || die "Invalid IP address '${VM_IP}'"
[[ "$GATEWAY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Invalid gateway '${GATEWAY}'"
[[ -z "$VLAN" || ( "$VLAN" =~ ^[0-9]+$ && "$VLAN" -ge 1 && "$VLAN" -le 4094 ) ]] || die "Invalid VLAN ID '${VLAN}'"
[[ -z "$SEARCHDOMAIN" || "$SEARCHDOMAIN" =~ ^[A-Za-z0-9.\ -]+$ ]] || die "Invalid search domains '${SEARCHDOMAIN}'"
[[ "$CINIT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username '${CINIT_USER}'"
[[ "$CPU_CORES" =~ ^[0-9]+$ && "$CPU_CORES" -ge 1 ]] || die "Invalid CPU core count"
[[ -n "$MEMORY" && "$MEMORY" -ge 512 ]] || die "Memory must be at least 512 MB"
[[ -n "$DISK_SIZE" ]] || die "Invalid disk size"
if [[ "$SECOND_DISK" == "yes" ]]; then
    [[ -n "$DISK2_SIZE" ]] || die "Invalid second disk size"
fi
if [[ -n "$SSH_KEYS_FILE" && ! -r "$SSH_KEYS_FILE" ]]; then
    die "SSH keys file '${SSH_KEYS_FILE}' is not readable"
fi

# ------------------------------------------------------------ image download
if [[ ! -f "$IMAGE_FILENAME" ]]; then
    echo -e "File ${GN}${IMAGE_FILENAME}${NC} does not exist. Downloading...\n"
    tmp_image="${IMAGE_FILENAME}.part"
    if wget -O "$tmp_image" "$DOWNLOAD_URL"; then
        mv "$tmp_image" "$IMAGE_FILENAME"
        echo ""
    else
        rm -f "$tmp_image"
        die "Failed to download $DOWNLOAD_URL"
    fi
fi

# A disk can only grow: refuse a size below the image's virtual size
image_gb="$(LC_ALL=C qemu-img info "$IMAGE_FILENAME" | awk '/^virtual size/ {gsub(/[(]/, ""); print $(NF-1); exit}')"
[[ "$image_gb" =~ ^[0-9]+$ ]] || die "Could not read the virtual size of ${IMAGE_FILENAME}"
image_gb=$(((image_gb + 1073741823) / 1073741824))
if ((DISK_SIZE < image_gb)); then
    die "Disk size ${DISK_SIZE}GB is smaller than the image (${image_gb}GB). Use a larger size, or delete
  ${IMAGE_FILENAME} to re-download the original image (it may have been enlarged by an older version of this script)."
fi

# ------------------------------------------------------------ vendor snippet
vendor_template="$SCRIPT_DIR/templ-vendor-data-${DISTRO_FAMILY}"
[[ -f "$vendor_template" ]] || die "Template $vendor_template not found"
SNIPPET_NAME="vendor-${VM_ID}.yaml"
SNIPPET_FILE="$snippet_dir/$SNIPPET_NAME"
sed "s|todo_timezone|${TIMEZONE}|g" "$vendor_template" > "$SNIPPET_FILE"

# --------------------------------------------------------------- create VM
echo -e "Creating the VM. Importing the main disk will take a moment.\n"

qm create "$VM_ID" --name "$VM_NAME" --ostype l26 \
    --memory "$MEMORY" \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 "${STORAGE}:0,pre-enrolled-keys=0" \
    --cpu "$CPU_TYPE" --sockets 1 --cores "$CPU_CORES" \
    --vga serial0 --serial0 socket \
    --net0 "virtio,bridge=${BRIDGE}${VLAN:+,tag=${VLAN}}" \
    --tags cloud-init > /dev/null
VM_CREATED=true

# Import straight from the cached image (never modified) and grow the copy
qm set "$VM_ID" \
    --scsihw virtio-scsi-pci \
    --virtio0 "${STORAGE}:0,import-from=${IMAGE_FILENAME},discard=on" \
    --boot order=virtio0 > /dev/null
qm disk resize "$VM_ID" virtio0 "${DISK_SIZE}G" > /dev/null

if [[ "$SECOND_DISK" == "yes" ]]; then
    qm set "$VM_ID" --virtio1 "${STORAGE}:${DISK2_SIZE},discard=on" > /dev/null
fi

# Native cloud-init drive
cloudinit_args=(
    --ide2 "${STORAGE}:cloudinit"
    --ciuser "$CINIT_USER"
    --cipassword "$(printf '%s' "$CINIT_PASSWORD" | openssl passwd -6 -stdin)"
    --ipconfig0 "ip=${VM_IP},gw=${GATEWAY}"
    --nameserver "$NAMESERVER"
    --cicustom "vendor=${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}"
)
[[ -z "$SEARCHDOMAIN" ]] || cloudinit_args+=(--searchdomain "$SEARCHDOMAIN")
[[ -z "$SSH_KEYS_FILE" ]] || cloudinit_args+=(--sshkeys "$SSH_KEYS_FILE")
qm set "$VM_ID" "${cloudinit_args[@]}" > /dev/null

qm start "$VM_ID"

# ------------------------------------------------------------------ summary
MEMORY_GB="$(awk -v m="$MEMORY" 'BEGIN {printf "%.1f", m/1024}')"
MEMORY_GB="${MEMORY_GB%.0}"
DISK2=""
[[ "$SECOND_DISK" != "yes" ]] || DISK2="\n  Secondary disk: ${GN}${DISK2_SIZE}GB${NC}"

echo -e "VM created successfully and started with the following parameters:"
echo -e "  Distro: ${GN}${DISTRO_NAME}${NC}\n  ID: ${GN}${VM_ID}${NC}\n  Name: ${GN}${VM_NAME}${NC}\n  RAM: ${GN}${MEMORY_GB}GB${NC}\n  CPU type: ${GN}${CPU_TYPE}${NC}  cores: ${GN}${CPU_CORES}${NC}\n  Primary disk: ${GN}${DISK_SIZE}GB${NC}${DISK2}\n  Storage: ${GN}${STORAGE}${NC}\n  Search domains: ${GN}${SEARCHDOMAIN:-none}${NC}\n  Address: ${GN}${VM_IP}${NC}  gateway: ${GN}${GATEWAY}${NC}  user: ${GN}${CINIT_USER}${NC}"
echo ""
