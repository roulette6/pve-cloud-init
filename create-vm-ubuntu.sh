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

echo -e "\nThis script will create an ${YL}Ubuntu 24.04 (Noble)${NC} VM using a cloud image.\n"

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

# Prompt for hostname, ID, and last subnet octet
read_colored "Storage for VM (local-lvm, pve-zpool, etc.): " vm_storage
read_colored "VM ID: " vm_id
read_colored "VM name: " vm_name
read_colored "VM CPU type (default is x86-64-v3): " cpu_type
read_colored "VM RAM amount in MB (default is 4096): " vm_memory
read_colored "VM disk size in GB (default is 20G): " vm_disk_size
read_colored "VM IP address: " vm_ip
read_colored "cloud-init username (example, john): " cinit_user
read_colored "cloud-init full name (example, John Smith): " cinit_gecos
read_colored "Do you want a second disk? (yes/no): " second_disk

# Ask for second disk size only if answered yes
if [[ "$second_disk" == "yes" ]]; then
    read_colored "Second disk size in GB: (default is 30G): " second_disk_size
fi

echo ""

# Check if any required variable is empty
if [[ -z "$vm_name" || -z "$vm_id" || -z "$vm_ip" ]]; then
    echo -e "Error: hostname, ID, and IP address cannot be empty" >&2
    exit 1
fi

# Set defaults for values not provided
if [[ -z "$vm_memory" ]]; then
    vm_memory="4096"
else
    vm_memory=${vm_memory//[!0-9]/}
fi

if [[ -z "$cpu_type" ]]; then
    cpu_type="x86-64-v3"
fi

if [[ -z "$vm_disk_size" ]]; then
    vm_disk_size="20G"
else
    vm_disk_size=${vm_disk_size//[!0-9]/}G
fi

if [[ "$second_disk" == "yes" && -z "$second_disk_size" ]]; then
    second_disk_size="30"
else
    second_disk_size=${second_disk_size//[!0-9]/}
fi

echo -e "Creating the VM. Importing the main disk will take a moment.\n"
qemu-img resize $cloud_img_path $vm_disk_size 1> /dev/null &

spin $!

qm create $vm_id --name "$vm_name" --ostype l26 \
    --memory $vm_memory \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $vm_storage:0,pre-enrolled-keys=0 \
    --cpu $cpu_type --socket 1 --cores 2 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0 > /dev/null &

spin $!

# Copy cloud-init template files and modify the copies
cd_storage="local"

cp ./templ-meta-data ./meta-data
cp ./templ-user-data ./user-data
cp ./templ-network-config ./network-config

# Get VM MAC address
vm_mac=$(grep -oP 'virtio=\K[A-F0-9:]{17}' /etc/pve/qemu-server/$vm_id.conf | tr '[:upper:]' '[:lower:]')

sed -i "s|todo_hostname|${vm_name}|g" meta-data
sed -i "s|todo_hostname|${vm_name}|g" user-data
sed -i "s|todo_group|sudo|g" user-data
sed -i "s|todo_ip|${vm_ip}|g" network-config
sed -i "s|todo_mac|${vm_mac}|g" network-config
sed -i "s|todo_user|${cinit_user}|g" user-data
sed -i "s|todo_gecos|${cinit_gecos}|g" user-data

# Create cloud-init ISO
genisoimage \
    -output /var/lib/vz/template/iso/$vm_id.iso -input-charset utf-8 \
    -volid cidata -rational-rock -joliet \
    user-data meta-data network-config &> /dev/null &

spin $!

# Configure the VM hardware
qm importdisk $vm_id $cloud_img_path $vm_storage 1> /dev/null &
spin $!

qm set $vm_id --scsihw virtio-scsi-pci --virtio0 "$vm_storage:vm-$vm_id-disk-1,discard=on" 1> /dev/null &
spin $!

qm set $vm_id --boot c --bootdisk virtio0 1> /dev/null &
spin $!

qm set $vm_id --ide2 $cd_storage:iso/$vm_id.iso,media=cdrom 1> /dev/null &
spin $!

qm set $vm_id --tags cloud-init 1> /dev/null

# Create secondary storage disk if requested
if [[ -n "$second_disk_size" ]]; then
    qm set $vm_id --virtio1 $vm_storage:$second_disk_size,discard=on 1> /dev/null &
    spin $!
fi

# start the VM
qm start $vm_id

echo -e "VM created successfully and started with the following parameters:"
echo -e "  ID: ${GN}${vm_id}${NC}\n  Name: ${GN}${vm_name}${NC}\n  RAM: ${GN}${vm_memory}MB${NC}\n  CPU type: ${GN}${cpu_type}${NC}\n  Primary disk size: ${GN}${vm_disk_size}B${NC}"
if [[ -n "$second_disk_size" ]]; then
    echo -e "  Secondary disk size: ${GN}${second_disk_size}GB${NC}"
fi
echo ""
