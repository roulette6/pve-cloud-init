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
    - `nameservers` \> `addresses`: Change to desired DNS servers
    - `nameservers` \> `search`: Add if you use internal DNS
4.  Execute the shell script based on the VM image you want. Answer a few questions, and wait for the VM to be created.

## Example usage

Download git repo

``` shell
git clone https://github.com/roulette6/pve-cloud-init.git \
    /var/lib/vz/template/iso/pve-cloud-init
cd /var/lib/vz/template/iso/pve-cloud-init
chmod +x *.sh
```

## Modify cloud-init files

This only needs to be done once.

### templ-user-data

Save your authorized keys to a temporary file

``` shell
cat << EOF > ./authorized_keys.txt
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIMt9pihqR99MAoguNURzuUn2EHY6TQ8tlq2XJDwDdC
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILt7jDru/vge2Ya47nGp69OyJ10T3KEx2ukGrj/M6hMi
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsDzbTG1lav30UUInt9fW9/CIBGzodrKzP29ET5CJaK
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOOWBiuNbvSPbDEia4DJLgOt3Iwqvqj/OuEutTQO/hiN
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBUyrWL8KBrk7u9nL1jEkhwuS0HgQ4MoUrW3dF1rOIR7
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHe0Jot8YOAge5u8yhCrW9y8BZx3/9Iy8FDrV5NTHOu1
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDTbS8MnRihYYduAfc79FMsNMjnYUTbb3xzm+8es6uIK
    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyLMd/Anlet3NNgC+CROaASE4qqXjAOegjmFWXrlciR
EOF
```

Delete any potential ssh key entries that might already exist and insert the ones from the file after the `ssh_authorized_keys` section.

``` shell
sed -i '/- ssh-ed25519/d' templ-user-data
sed -i '/ssh_authorized_keys/r ./authorized_keys.txt' templ-user-data
```

### templ-network-config

Update the default gateway

``` shell
sed -i "s|via: TODO|via: 192.168.128.1|" templ-network-config
```

Modify the DNS servers as desired

``` shell
sed -i "/1.1.1.1/d" templ-network-config
sed -i "s|8.8.8.8|192.168.129.16|" templ-network-config
```

Add your own DNS search zones if you’d like

``` shell
cat << EOF >> templ-network-config
        search:
          - example.com
          - home.example.com
EOF
```

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
