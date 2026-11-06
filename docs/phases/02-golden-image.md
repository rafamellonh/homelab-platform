# Phase 2 — Golden image

## 1. Goal

Build an Ubuntu 24.04 LTS template that every VM of the project is cloned from.
Each clone must boot with its own hostname, IP address, user, SSH key, host keys and `machine-id`,
all injected by cloud-init — nothing specific to one machine is kept in the image.

## 2. Prerequisites

- [Phase 1](01-proxmox.md) completed (both nodes updated, cluster quorate)
- An SSH key pair on the admin workstation (`ssh-keygen -t ed25519`)
- Ubuntu 24.04 live server ISO in the `local` storage of the node where the install happens

### Approach

The template was built by **installing Ubuntu from the ISO** on one node, generalizing the installed
system and converting it into a template. This was a deliberate choice to understand every step.
The alternative — importing the official Ubuntu cloud image (`noble-server-cloudimg-amd64.img`) — is
faster and easier to automate, and is a candidate for a scripted rebuild in [Phase 13](13-rebuild.md).

Because storage is local to each node, a template can only be cloned on the node that holds its disk.
One template exists on each node:

| VMID | Name | Node |
|---|---|---|
| 9000 | `tpl-ubuntu-2404-srv01` | srv01 |
| 9001 | `tpl-ubuntu-2404-srv02` | srv02 (built here, then copied to srv01) |

### References

| Topic | Link |
|---|---|
| Ubuntu Server installation | https://ubuntu.com/server/docs/install/general |
| Proxmox cloud-init support | https://pve.proxmox.com/wiki/Cloud-Init_Support |
| Proxmox VM templates and clones | https://pve.proxmox.com/pve-docs/chapter-qm.html#qm_templates |
| cloud-init documentation | https://docs.cloud-init.io/ |

## 3. Step by step

### 3.1 Download the ISO (srv02)

```bash
cd /var/lib/vz/template/iso
wget -O ubuntu-24.04.5-live-server-amd64.iso https://releases.ubuntu.com/24.04.5/ubuntu-24.04.5-live-server-amd64.iso
wget https://releases.ubuntu.com/24.04.5/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

The ISO is only needed during the install and can be removed once the templates exist.

### 3.2 Create the VM

```bash
qm create 9001 --name tpl-ubuntu-2404-srv02 --ostype l26 \
  --cpu x86-64-v3 --cores 2 --memory 2048 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single \
  --scsi0 local-lvm:20,discard=on,ssd=1 \
  --ide2 local:iso/ubuntu-24.04.5-live-server-amd64.iso,media=cdrom \
  --boot order='scsi0;ide2' --agent enabled=1 \
  --tags template,ubuntu-2404
qm start 9001
```

- `x86-64-v3`: same CPU type on both nodes, so VMs can migrate between different CPU generations.
- `discard=on,ssd=1`: freed blocks are returned to the thin pool.
- `agent enabled=1`: Proxmox talks to the QEMU guest agent (IP addresses, clean shutdown).

### 3.3 Install Ubuntu

| Screen | Choice | Why |
|---|---|---|
| Language | English | Consistent with the documentation |
| Type of install | Ubuntu Server (not minimized) | Standard server tooling |
| Network | DHCP | Temporary; replaced by cloud-init on each clone |
| Storage | Entire disk, **LVM disabled** | A plain partition lets cloud-init grow the disk automatically when a clone gets a bigger disk |
| Profile | user `rafael`, hostname `tpl-ubuntu-2404` | Hostname is replaced by cloud-init on each clone |
| Ubuntu Pro | Skip | Not needed for the lab |
| SSH | OpenSSH server, password login allowed | Needed to finish the setup; keys are injected later by cloud-init |
| Snaps | none | Keep the image small |

![Storage layout without LVM](../images/phase-02/storage.png)

Expected storage summary: a single `/` (ext4, ~20 GB) on a plain partition, plus the 1 MB BIOS grub spacer.

> **Why not LVM?** With LVM, cloud-init grows only the partition (the physical volume). The volume group,
> logical volume and file system would need `pvresize`, `lvextend` and `resize2fs` on every clone.
> The Ubuntu installer with LVM also uses only half of the disk by default. In a VM, the hypervisor
> already provides snapshots and disk resizing, so LVM adds a layer without real benefit here.

### 3.4 Post-install (inside the VM)

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent cloud-init
sudo systemctl start qemu-guest-agent
```

From the node:

```bash
qm agent 9001 ping && echo "agent OK"
```

### 3.5 Generalize (inside the VM)

Remove everything that is unique to this installation, so that every clone is born as a new machine
(the Linux equivalent of Windows Sysprep):

```bash
sudo rm -f /etc/netplan/*.yaml
sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/cloud.cfg.d/90-installer-network.cfg
sudo rm -f /etc/ssh/ssh_host_*
sudo cloud-init clean --logs --seed --machine-id
sudo apt clean
sudo shutdown -h now
```

| Removed | Problem if kept |
|---|---|
| `99-installer.cfg` | The installer's cloud-init settings would override the data provided by Proxmox |
| `90-installer-network.cfg`, `/etc/netplan/*.yaml` | The install-time network would be fixed in every clone |
| `/etc/ssh/ssh_host_*` | Every clone would share the same SSH identity |
| `machine-id` | Clones could get the same DHCP lease and be confused by systemd and logging |
| cloud-init logs and seed | cloud-init would consider itself already run and skip the clones' first boot |

> After this step the VM has no network configuration. It must not be started again before
> becoming a template.

### 3.6 Cloud-init drive and template (srv02)

Copy the public key from the workstation:

```bash
scp ~/.ssh/id_ed25519.pub root@192.168.2.171:/root/rafael.pub
```

Replace the ISO with a cloud-init drive and set the defaults:

```bash
qm set 9001 --delete ide2
qm set 9001 --ide2 local-lvm:cloudinit --boot order=scsi0
qm set 9001 --ciuser rafael --sshkeys /root/rafael.pub \
  --ipconfig0 ip=dhcp --nameserver 8.8.8.8 --searchdomain rafaelmellonh.com.br
qm template 9001
```

```bash
qm config 9001 | grep -E "template|boot|ide2|scsi0|ciuser|ipconfig0|nameserver|searchdomain|agent|cpu"
```

```
agent: enabled=1
boot: order=scsi0
ciuser: rafael
cpu: x86-64-v3
ide2: local-lvm:vm-9001-cloudinit,media=cdrom
ipconfig0: ip=dhcp
nameserver: 8.8.8.8
scsi0: local-lvm:base-9001-disk-0,discard=on,size=20G,ssd=1
searchdomain: rafaelmellonh.com.br
template: 1
```

These are only defaults: Terraform overrides name, IP, CPU, memory and disk size for each VM.

### 3.7 How a clone gets its identity

1. The cloud-init drive is a small virtual CD-ROM where Proxmox writes *meta-data* (hostname),
   *user-data* (user, SSH key) and *network-config* (from `ipconfig0`) in the NoCloud format.
2. When a VM is cloned, Proxmox regenerates that drive with the clone's own values.
3. On first boot, cloud-init reads the drive and writes `/etc/netplan/50-cloud-init.yaml`, sets the
   hostname, creates the user with the SSH key and generates new host keys and `machine-id`.

### 3.8 Copy the template to srv01

Proxmox cannot clone directly to another node when the disk is on local storage (`--target` requires
shared storage). The template is cloned locally and the clone is migrated while powered off:

```bash
# srv02
qm clone 9001 9000 --name tpl-ubuntu-2404-srv01 --full
qm migrate 9000 srv01 --with-local-disks --targetstorage local-lvm

# srv01
qm template 9000
```

### 3.9 Clean-up

```bash
qm destroy 100 --purge                                              # old Ubuntu 22.04 template
rm /var/lib/vz/template/iso/ubuntu-24.04.5-live-server-amd64.iso    # optional
```

## 4. Validation

Test clone on srv02:

```bash
qm clone 9001 199 --name test-golden --full
qm set 199 --ipconfig0 ip=192.168.2.199/24,gw=192.168.2.1
qm start 199
qm agent 199 ping && echo "agent OK"
```

From the workstation, logging in with the SSH key (no password):

```bash
ssh rafael@192.168.2.199 'hostname; ip -4 -br a; cloud-init status; systemctl is-active qemu-guest-agent; cat /etc/machine-id'
```

```
test-golden
lo               UNKNOWN        127.0.0.1/8
eth0             UP             192.168.2.199/24
status: done
active
d8e466b96a4c477e82498218fba324fa
```

Network configuration generated by cloud-init (`/etc/netplan/50-cloud-init.yaml`):

```yaml
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: "bc:24:11:a2:de:31"
      addresses:
      - "192.168.2.199/24"
      nameservers:
        addresses:
        - 8.8.8.8
        search:
        - rafaelmellonh.com.br
      set-name: "eth0"
      routes:
      - to: "default"
        via: "192.168.2.1"
```

| Check | Expected | Result |
|---|---|---|
| Hostname from cloud-init | `test-golden` | ✅ |
| IP from `ipconfig0` | `192.168.2.199/24` | ✅ |
| cloud-init | `status: done` | ✅ |
| QEMU guest agent | `active`, `qm agent ping` OK | ✅ |
| New `machine-id` | different from the template | ✅ |
| SSH with key only | no password prompt | ✅ |
| Template on srv01 | `template: 1`, `base-9000-disk-0` | ✅ |

Remove the test clone:

```bash
qm stop 199 && qm destroy 199 --purge
```

## 5. Issues found and how they were solved

### Corrupted ISO

**Symptom:** the installer failed with *"Sorry, there was a problem completing the installation"* during a `curtin command in-target` step.

**Solution:** downloaded the ISO again and the installation completed. Verifying the download with
`sha256sum -c SHA256SUMS` before installing would have caught it.

### LVM enabled by default in the installer

**Symptom:** the storage summary showed `ubuntu-vg` / `ubuntu-lv` with a 10 GB `/` and 8 GB left free.

**Solution:** went back and unchecked *Set up this disk as an LVM group* (see section 3.3 for the reason).

### No network after the clean-up

**Symptom:** after removing the installer's network configuration and rebooting, `ens18` was `DOWN` and SSH was lost.

**Cause:** expected — the network configuration was removed on purpose, and the template has no
cloud-init drive yet to provide a new one.

**Solution:** to keep working over SSH, a temporary DHCP configuration was added from the console
(`sudo netplan set ethernets.ens18.dhcp4=true && sudo netplan apply`) and removed again in the final
clean-up (`rm -f /etc/netplan/*.yaml`). Lesson: the clean-up must be the last step before shutdown.

### SSH refused after removing the host keys

**Symptom:** the VM had an IP address but SSH connections failed.

**Cause:** `sshd` does not start without host keys.

**Solution:** `sudo ssh-keygen -A && sudo systemctl restart ssh` to work temporarily; the keys are removed
again in the final clean-up and cloud-init generates new ones on each clone.

### `qm set` aborted by a missing SSH key file

**Symptom:** `can't open '/root/rafael.pub' - No such file or directory`, and none of the cloud-init
options (`ciuser`, `ipconfig0`, `nameserver`, `searchdomain`) were applied.

**Cause:** `qm set` validates all options before applying them; one error aborts the whole command.

**Solution:** copied the key to the node and ran the `qm set` again. Cloud-init options can be changed
on an existing template.

### Interface named `eth0` instead of `ens18`

**Symptom:** in the clone, `ip a show ens18` returned *Device "ens18" does not exist*.

**Cause:** the network configuration generated from Proxmox matches the NIC by MAC address and renames it
(`set-name: "eth0"`).

**Solution:** expected behaviour; documented because Ansible and monitoring will reference the interface name (`eth0`).

### Cannot clone a template directly to another node

**Symptom:** `qm clone --target` only works when the source disk is on shared storage.

**Solution:** full clone on the same node, offline migration with `--with-local-disks`, then convert to a template (section 3.8).

## 6. Future improvements

- Script the template build (`scripts/`) from the official cloud image, for the rebuild in Phase 13
- Shared storage, so one template serves both nodes
- DNS of the template pointing to Technitium once `tools-01` exists
- Periodic rebuild of the template to include the latest updates
