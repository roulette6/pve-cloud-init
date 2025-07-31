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

1.  Clone this repo in the ISO templates directory
2.  Modify **templ-user-data**
    - `ssh_authorized_keys`
    - `packages`
    - `runcmd`
3.  Modify **templ-network-config**
    - `via`
    - `nameservers` \> `search`: Change if you use internal DNS
    - `nameservers` \> `addresses`: Change to desired DNS servers
4.  Execute the shell script based on the VM image you want. Answer a few questions, and wait for the VM to be created.

### Example usage

Download git repo

``` shell
git clone https://github.com/roulette6/pve-cloud-init.git \
    /var/lib/vz/template/iso/pve-cloud-init
cd /var/lib/vz/template/iso/pve-cloud-init
chmod +x *.sh
```

Modify YAML as indicated above (not shown here).

Create a VM

``` shell
./create-vm-ubuntu.sh
```

## A note for clusters with HA

> [!NOTE]
> If you place your VM in local storage capable of replication and HA, such as a ZFS pool, you’ll want to do one of the following.

### Transfer the cloud-init ISO to the other nodes

Ensure all nodes have the same cloud-init files in their local storage. This will ensure there are no errors if you migrate a VM from one node to the other.

### Disable cloud-init on the VM

When a VM created from a cloud image has been configured by a mounted cloud-init ISO, the ISO is required to remain mounted or the VM could lose some important configs. You can prevent this requirement by disabling cloud-init with the ISO still mounted. Once you’ve done this, you can safely remove the ISO from the VM and delete it. You can also delete the CD drive from the VM.

``` shell
# run this on the VM's CLI
sudo touch /etc/cloud/cloud-init.disabled
```

If you instead need to make changes to the cloud-init ISO and reattach it so the VM can bootstrap itself again, run the command below, shut down the VM, attach the new ISO, and turn on the VM.

``` shell
# run this on the VM's CLI
sudo cloud-init clean
```
