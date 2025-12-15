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

spin() {
    local pid=$1
    while kill -0 $pid 2>/dev/null; do
        printf '\r|'; sleep 0.1
        printf '\r/'; sleep 0.1
        printf '\r-'; sleep 0.1
        printf '\r\'; sleep 0.1
    done
    printf '\r'
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

This script creates an Ubuntu 24.04 (Noble) VM using a cloud image.

OPTIONS:
    -s, --storage STORAGE          Storage location for VM
    -i, --id VM_ID                 VM ID number
    -n, --name VM_NAME             VM hostname
    -t, --cpu CPU_TYPE             CPU type (default: x86-64-v3)
    -c, --cpu-cores CPU_CORES      CPU cores (default: 2)
    -m, --memory MEMORY            RAM in MB (default: 4096)
    -d, --disk-size DISK_SIZE      Primary disk size in GB (default: 20)
    -a, --ip IP_ADDRESS            VM IP address
    -u, --user USERNAME            Cloud-init username (also used for geckos)
    -2, --disk2-size DISK2_SIZE    Second disk size in GB (optional)
    -h, --help                     Show this help message

EXAMPLES:
    # Interactive mode (prompts for all values)
    $0

    # Fully specified
    $0 \\
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

echo -e "\nThis script will create an ${YL}Ubuntu 24.04 (Noble)${NC} VM using a cloud image.\n"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Download the cloud image if it doesn't exist.
cloud_img_path="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"
download_url="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

if [ ! -f "$cloud_img_path" ]; then
    echo -e "File ${GN}${cloud_img_path}${NC} does not exist. Downloading...\n"

    # Download the file
    if wget -O "$cloud_img_path" "$download_url"; then
        echo -e "Image downloaded. Installing ${GN}qemu-guest-agent${NC} in the image."
        virt-customize --install qemu-guest-agent -a $cloud_img_path &> /dev/null &
        spin $!
        echo ""
    else
        echo -e "Error: Failed to download file from $download_url"
        [ -f "$cloud_img_path" ] && rm -f "$cloud_img_path"
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
    read_colored "Storage location for VM ($locations): " STORAGE
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
    read_colored "VM CPU cores (default is x86-64-v3): " CPU_CORES
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

if [[ -z "$vm_disk_size" ]]; then
    vm_disk_size="20G"
else
    vm_disk_size=${vm_disk_size//[!0-9]/}G
fi

if [[ "$SECOND_DISK" == "yes" && -z "$DISK2_SIZE" ]]; then
    DISK2_SIZE="30"
else
    DISK2_SIZE=${DISK2_SIZE//[!0-9]/}
fi

echo -e "Creating the VM. Importing the main disk will take a moment.\n"
qemu-img resize $cloud_img_path $vm_disk_size 1> /dev/null &

spin $!

qm create $VM_ID --name "$VM_NAME" --ostype l26 \
    --memory $MEMORY \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $STORAGE:0,pre-enrolled-keys=0 \
    --cpu $CPU_TYPE --socket 1 --cores $CPU_CORES \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0 > /dev/null &

spin $!

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
qm importdisk $VM_ID $cloud_img_path $STORAGE 1> /dev/null &
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
echo -e "  ID: ${GN}${VM_ID}${NC}\n  Name: ${GN}${VM_NAME}${NC}\n  RAM: ${GN}${MEMORY_GB}GB${NC}\n  CPU type: ${GN}${CPU_TYPE}${NC}  cores: ${GN}${CPU_CORES}${NC}\n  Primary disk: ${GN}${vm_disk_size}B${NC}${DISK2}"
echo ""
