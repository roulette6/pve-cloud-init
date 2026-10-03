# Proxmox Virtual Environment cloud-init

Creates VMs from cloud images using Proxmox's **native cloud-init drive** (no ISO files).

- Downloads the cloud image if it isn't cached (the cached image is never modified).
- Imports the image as the VM disk and resizes the copy.
- Configures user, hashed password, SSH keys, IP/gateway and DNS through the Proxmox cloud-init drive.
- Attaches a small *vendor-data* snippet for timezone, packages and commands.

## Requirements

- Proxmox VE 8.1+ (uses `import-from`), run as root on the node.
- `openssl` and `wget` (present on a default install).
- A storage with the **Snippets** content type enabled (default: `local`). Enable it under *Datacenter > Storage*.

## Setup (once)

```shell
git clone https://github.com/roulette6/pve-cloud-init.git /root/pve-cloud-init
cd /root/pve-cloud-init
cp pve-cloud-init.conf.example pve-cloud-init.conf
```

1. Edit **pve-cloud-init.conf**: DNS, search domain, timezone, bridge, and `SSH_KEYS_FILE` (a file with one public key per line).
2. Edit **templ-vendor-data-debian** / **templ-vendor-data-rhel** for the packages and commands you want. `todo_timezone` is replaced by the script.

User, password, SSH keys and network are *not* in the templates any more; Proxmox generates them from the VM's cloud-init settings.

## Usage

Anything not given on the command line is prompted for, including the password (hidden, entered twice; or set `CINIT_PASSWORD`). The password is hashed (SHA-512) before it is given to Proxmox.

The DNS search domains are also prompted for (default from `SEARCHDOMAIN` in the config; type `none` for none, or use `--search-domain`). If `--storage` is missing or doesn't exist, the available storages are listed and you pick one by number.

Valid distributions: `ubuntu` (26.04 LTS), `debian` (13), `alma` (10), `centos` (Stream 10), `fedora` (43).

```shell
./create-vm.sh \
  --distro debian \
  --storage crucial \
  --id 149 \
  --name test149 \
  --cpu-type x86-64-v3 \
  --cpu-cores 2 \
  --memory 6144 \
  --disk-size 30 \
  --ip 192.168.1.149/24 \
  --gateway 192.168.1.1 \
  --user john \
  --disk2-size 30
```

Use `--second-disk no` to skip the second disk prompt. The second disk is attached but not partitioned or formatted.

If anything fails after the VM is created, the script destroys the partial VM and its snippet.

## Clusters / HA

Snippets on `local` are per node. For migration or HA, put snippets on shared storage (e.g. CephFS/NFS) and set `SNIPPET_STORAGE` accordingly, or copy `snippets/vendor-<id>.yaml` to every node. The cloud-init drive itself lives on the VM's storage and migrates with it.

To re-run cloud-init after changing settings: `qm cloudinit update <id>`, then `sudo cloud-init clean` inside the VM and reboot.
