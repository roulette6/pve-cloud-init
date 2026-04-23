#!/bin/bash

# Exit immediately if any command fails
set -e

# Set colors
GN='\033[0;32m'
BL='\033[0;34m'
YL='\033[1;33m'
CY='\033[0;36m'
NC='\033[0m' # No Color (reset)

# functions
read_colored() {
    local prompt="$1"
    local var_name="$2"
    echo -n "$prompt"
    echo -ne "$GN"  # Set color for input
    read "$var_name"
    echo -ne "$NC"     # Reset color
}

select_distribution() {
    local distro_choice
    local use_param=false

    # Check if DISTRIBUTION variable is set and valid
    if [[ -n "$DISTRIBUTION" ]]; then
        case "${DISTRIBUTION,,}" in
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
    fi

    # Interactive prompt if DISTRIBUTION not set or invalid
    if [[ "$use_param" == false ]]; then
        echo -e "${BL}Select a Linux distribution:${NC}\n"
        echo "  1) Ubuntu 24.04 LTS"
        echo "  2) Debian 13"
        echo "  3) Alma Linux 10"
        echo "  4) CentOS Stream 10"
        echo "  5) Fedora 43"
        echo ""
        read_colored "Enter selection (1-5): " distro_choice
        echo ""
    fi

    # Set variables based on choice
    case $distro_choice in
        1)
            DISTRO_NAME="Ubuntu 24.04 LTS"
            IMAGE_FILENAME="/var/lib/vz/template/iso/ubuntu-2404.img"
            DOWNLOAD_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
            DISTRO_FAMILY="debian"
            ;;
        2)
            DISTRO_NAME="Debian 13"
            IMAGE_FILENAME="/var/lib/vz/template/iso/debian-13.img"
            DOWNLOAD_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
            DISTRO_FAMILY="debian"
            ;;
        3)
            DISTRO_NAME="Alma Linux 10"
            IMAGE_FILENAME="/var/lib/vz/template/iso/almalinux-10.img"
            DOWNLOAD_URL="https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        4)
            DISTRO_NAME="CentOS Stream 10"
            IMAGE_FILENAME="/var/lib/vz/template/iso/centos-10.img"
            DOWNLOAD_URL="https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        5)
            DISTRO_NAME="Fedora 43"
            IMAGE_FILENAME="/var/lib/vz/template/iso/fedora-43.img"
            DOWNLOAD_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"
            DISTRO_FAMILY="rhel"
            ;;
        *)
            echo -e "${YL}Invalid selection.${NC} Please run the script again and choose 1-5."
            exit 1
            ;;
    esac

    if [[ "$use_param" == true ]]; then
        echo -e "Using distribution from parameter: ${GN}${DISTRO_NAME}${NC}\n"
    else
        echo -e "Selected: ${GN}${DISTRO_NAME}${NC}\n"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

This script creates an Ubuntu 24.04 (Noble) VM using a cloud image.

OPTIONS:
    --distro DISTRIBUTION          ubuntu, debian, alma, centos, fedora
    -s, --storage STORAGE          Storage location for VM
    -i, --id VM_ID                 VM ID number
    -n, --name VM_NAME             VM hostname
    -t, --cpu CPU_TYPE             CPU type (default: x86-64-v3)
    -c, --cpu-cores CPU_CORES      CPU cores (default: 2)
    -m, --memory MEMORY            RAM in MB (default: 4096)
    -d, --disk-size DISK_SIZE      Primary disk size in GB (default: 20)
    -a, --ip IP_ADDRESS            VM IP address
    -u, --user USERNAME            Cloud-init username (also used for geckos)
    --second-disk SECOND_DISK      Whether to include a secondn disk (yes/no)
    -2, --disk2-size DISK2_SIZE    Second disk size in GB (optional)
    -h, --help                     Show this help message

EXAMPLES:
    # Interactive mode (prompts for all values)
    $0

    # Fully specified
    $0 \\
    --distro alma \\
    --storage crucial \\
    --id 149 \\
    --name test149 \\
    --cpu-type x86-64-v3 \\
    --cpu-cores 2 \\
    --memory 6144 \\
    --disk-size 30 \\
    --ip 192.168.1.149 \\
    --user john \\
    --disk2-size 30

    # Partial specification (prompts for missing values)
    $0 --id 100 --name myvm --ip 192.168.1.100

EOF
}

echo -e "\nThis script will create a ${YL}${DISTRO_NAME}${NC} VM using a cloud image.\n"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --distro)
            DISTRIBUTION="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE="$2"
            shift 2
            ;;
        -i|--id)
            VM_ID="$2"
            shift 2
            ;;
        -n|--name)
            VM_NAME="$2"
            shift 2
            ;;
        -t|--cpu-type)
            CPU_TYPE="$2"
            shift 2
            ;;
        -c|--cpu-cores)
            CPU_CORES="$2"
            shift 2
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -d|--disk-size)
            DISK_SIZE="$2"
            shift 2
            ;;
        --second-disk)
            SECOND_DISK="$2"
            shift 2
            ;;
        -a|--ip)
            vm_ip="$2"
            shift 2
            ;;
        -u|--user)
            cinit_user="$2"
            shift 2
            ;;
        -2|--disk2-size)
            DISK2_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${YL}Unknown option:${NC} $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if genisoimage is installed
if ! command -v genisoimage >/dev/null 2>&1; then
    echo -e "${YW}genisoimage${NC} not found. Please install it and try again."
    exit 1
fi

# Set distribution
select_distribution $DISTRIBUTION

# Download the cloud image if it doesn't exist.
if [ ! -f "$IMAGE_FILENAME" ]; then
    echo -e "File ${GN}${IMAGE_FILENAME}${NC} does not exist. Downloading...\n"

    # Download the file
    if wget -O "$IMAGE_FILENAME" "$DOWNLOAD_URL"; then
        echo -e "Image downloaded. Installing ${GN}qemu-guest-agent${NC} in the image."
        virt-customize --install qemu-guest-agent -a $IMAGE_FILENAME &> /dev/null &
        spin $!
        echo ""
    else
        echo -e "Error: Failed to download file from $DOWNLOAD_URL"
        [ -f "$IMAGE_FILENAME" ] && rm -f "$IMAGE_FILENAME"
        exit 1
    fi
fi

# Get list of storage locations that can store VM images
locations="$(
    pvesm status --content images \
        | awk 'NR>1 {print $1}' \
        | tr '\n' ' ' \
        | sed 's/ $//; s/ /, /'
)"

# Prompt for variables if they weren't set when the script was called
if [[ -z "$STORAGE" ]]; then
    read_colored "Select VM location from these options ($locations): " STORAGE
fi

if [[ -z "$VM_ID" ]]; then
    read_colored "VM ID: " VM_ID
fi

if [[ -z "$VM_NAME" ]]; then
    read_colored "VM name: " VM_NAME
fi

if [[ -z "$CPU_TYPE" ]]; then
    read_colored "VM CPU type (default is x86-64-v3): " CPU_TYPE
fi

if [[ -z "$CPU_CORES" ]]; then
    read_colored "VM CPU cores (default is 2): " CPU_CORES
fi

if [[ -z "$MEMORY" ]]; then
    read_colored "VM RAM amount in MB (default is 4096): " MEMORY
fi

if [[ -z "$DISK_SIZE" ]]; then
    read_colored "VM disk size in GB (default is 20G): " DISK_SIZE
fi

if [[ -z "$vm_ip" ]]; then
    read_colored "VM IP address: " vm_ip
fi

if [[ -z "$cinit_user" ]]; then
    read_colored "cloud-init username (example, john): " cinit_user
fi

if [[ "$DISK2_SIZE" ]]; then
    SECOND_DISK="yes"
fi

if [[ -z "$SECOND_DISK" ]]; then
    read_colored "Do you want a second disk? (yes/no): " SECOND_DISK
fi

# Ask for second disk size only if answered yes
if [[ "$SECOND_DISK" == "yes" && -z "$DISK2_SIZE" ]]; then
    read_colored "Second disk size in GB: (default is 30G): " DISK2_SIZE
fi

echo ""

# Check if any required variable is empty
if [[ -z "$VM_NAME" || -z "$VM_ID" || -z "$vm_ip" ]]; then
    echo -e "Error: hostname, ID, and IP address cannot be empty" >&2
    exit 1
fi

# Set defaults for values not provided
if [[ -z "$MEMORY" ]]; then
    MEMORY="4096"
else
    MEMORY=${MEMORY//[!0-9]/}
fi

if [[ -z "$CPU_TYPE" ]]; then
    CPU_TYPE="x86-64-v3"
fi

if [[ -z "$CPU_CORES" ]]; then
    CPU_CORES="2"
fi

if [[ -z "$DISK_SIZE" ]]; then
    DISK_SIZE="20G"
else
    DISK_SIZE=${DISK_SIZE//[!0-9]/}G
fi

if [[ "$SECOND_DISK" == "yes" && -z "$DISK2_SIZE" ]]; then
    DISK2_SIZE="30"
else
    DISK2_SIZE=${DISK2_SIZE//[!0-9]/}
fi

echo -e "Creating the VM. Importing the main disk will take a moment.\n"
qemu-img resize $IMAGE_FILENAME $DISK_SIZE 1> /dev/null

qm create $VM_ID --name "$VM_NAME" --ostype l26 \
    --memory $MEMORY \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 ${STORAGE}:0,pre-enrolled-keys=0 \
    --cpu $CPU_TYPE --socket 1 --cores $CPU_CORES \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0 > /dev/null

# Get VM MAC address for modifying cloud-init
vm_mac=$(
    grep -oP 'virtio=\K[A-F0-9:]{17}' /etc/pve/qemu-server/$VM_ID.conf \
    | tr '[:upper:]' '[:lower:]'
)

# Copy cloud-init template files and modify the copies
cd_storage="local"

cp ./templ-meta-data ./meta-data
cp ./templ-user-data ./user-data
cp ./templ-network-config ./network-config

sed -i "s|todo_hostname|${VM_NAME}|g" meta-data
sed -i "s|todo_hostname|${VM_NAME}|g" user-data
sed -i "s|todo_group|sudo|g" user-data
sed -i "s|todo_ip|${vm_ip}|g" network-config
sed -i "s|todo_mac|${vm_mac}|g" network-config
sed -i "s|todo_user|${cinit_user}|g" user-data
sed -i "s|todo_gecos|${cinit_user}|g" user-data

# Create cloud-init ISO
genisoimage \
    -output /var/lib/vz/template/iso/$VM_ID.iso -input-charset utf-8 \
    -volid cidata -rational-rock -joliet \
    user-data meta-data network-config &> /dev/null &

spin $!

# Configure the VM hardware
qm importdisk $VM_ID $IMAGE_FILENAME $STORAGE 1> /dev/null &
spin $!

qm set $VM_ID \
    --scsihw virtio-scsi-pci \
    --virtio0 \
    "$STORAGE:vm-$VM_ID-disk-1,discard=on" 1> /dev/null &
spin $!

qm set $VM_ID \
    --boot c \
    --bootdisk virtio0 1> /dev/null &
spin $!

qm set $VM_ID \
    --ide2 \
    $cd_storage:iso/$VM_ID.iso,media=cdrom 1> /dev/null &
spin $!

qm set $VM_ID \
    --tags cloud-init 1> /dev/null

# Create secondary storage disk if requested
if [[ -n "$DISK2_SIZE" ]]; then
    qm set $VM_ID \
        --virtio1 $STORAGE:$DISK2_SIZE,discard=on 1> /dev/null &
    spin $!
fi

# start the VM
qm start $VM_ID

# Print a summary of the VM created
MEMORY_GB=$(echo "scale=1; $MEMORY/1024" | bc) && MEMORY_GB=${MEMORY_GB%.0}
if [[ -n "$DISK2_SIZE" ]]; then
    DISK2="  Secondary disk: ${GN}${DISK2_SIZE}GB${NC}"
else
    DISK2=""
fi

echo -e "VM created successfully and started with the following parameters:"
echo -e "  Distro: ${GN}${DISTRO_NAME}${NC}\n  ID: ${GN}${VM_ID}${NC}\n  Name: ${GN}${VM_NAME}${NC}\n  RAM: ${GN}${MEMORY_GB}GB${NC}\n  CPU type: ${GN}${CPU_TYPE}${NC}  cores: ${GN}${CPU_CORES}${NC}\n  Primary disk: ${GN}${DISK_SIZE}B${NC}${DISK2}"
echo ""
