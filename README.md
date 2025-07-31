# Proxmox Virtual Environment cloud-init

This repo contains scripts to create VMs based on cloud-init templates. It does the following:

- Downloads the VM image if it doesn’t exist
- It creates a cloud-init ISO based on the data information provided.
- It creates a VM and attaches the cloud-init ISO.

## Requirements

- You must have `genisoimage` installed to generate an ISO file containing the cloud-init data. The cloud-init can be mounted as a CD when using a cloud image.
- You must update **templ-user-data** with your own SSH keys and commands.
- You must update **templ-network-config** with your own network information, leaving only `todo_ip` so it can be changed by the script.

## How to use

- Clone this repo in the ISO templates directory
- Execute the shell script based on the VM image you want. Answer a few questions, and wait for the VM to be created.

Example

```shell
git clone https://github.com/roulette6/pve-cloud-init.git \
    /var/lib/vz/template/iso/pve-cloud-init
cd /var/lib/vz/template/iso/pve-cloud-init
chmod +x *.sh

# Modify templ-user-data and templ-network-config before proceeding
./create-vm-ubuntu.sh
```

## Notes for clusters with HA

If you place your VM in local storage capable of replication and HA, such as a ZFS pool, you'll want to do one of the following:

- Transfer the cloud-init ISO to the local storage of the other nodes
- Disable cloud-init on the VM once it has gotten its configuration, remove the ISO, and delete both the ISO and CD drive.

### Disabling cloud-init

When a VM created from a cloud image has been configured by a mounted cloud-init ISO, the ISO is required to remain mounted lest the VM lose some important configs, such as networking or user information.

You can prevent this requirement by disabling cloud-init with the ISO still mounted. Once you've done this, you can safely remove the ISO from the VM and delete it.

```shell
sudo touch /etc/cloud/cloud-init.disabled
```

If you instead need to make changes to the cloud-init ISO and reattach it so the VM can bootstrap itself again, run the command below, shut down the VM, attach the new ISO, and turn on the VM.


```shell
sudo cloud-init clean
```
