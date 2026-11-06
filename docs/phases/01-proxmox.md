# Phase 1 — Proxmox installation & cluster

## 1. Goal

Install Proxmox VE on both physical hosts, join them in a cluster and bring both nodes to a known,
updated and documented baseline before any VM of the project is created.

## 2. Prerequisites

- Phase 0 completed (IP plan, naming conventions, domain)
- Virtualization (VT-x / VT-d) enabled in the BIOS of both hosts
- Proxmox VE 9 ISO on a USB stick
- Static IPs reserved for the hosts: `192.168.2.170` (srv01) and `192.168.2.171` (srv02)

### References

The installation and cluster setup followed the official Proxmox VE documentation (version 9.x at the time of writing):

| Topic | Link |
|---|---|
| System requirements | https://pve.proxmox.com/wiki/System_Requirements |
| Installation | https://pve.proxmox.com/pve-docs/chapter-pve-installation.html |
| Package repositories (no-subscription) | https://pve.proxmox.com/wiki/Package_Repositories |
| Cluster manager (`pvecm`) | https://pve.proxmox.com/pve-docs/chapter-pvecm.html |
| Storage (`local-lvm`, LVM-thin) | https://pve.proxmox.com/pve-docs/chapter-pvesm.html |
| Certificate management | https://pve.proxmox.com/pve-docs/chapter-sysadmin.html#sysadmin_certificate_management |
| Time synchronization | https://pve.proxmox.com/pve-docs/chapter-sysadmin.html#sysadmin_timesync |

Any deviation from the official guide is noted in the corresponding step.

## 3. Step by step

### 3.1 Installation

Both nodes were installed from the ISO with the default disk layout (LVM: `root`, `swap` and the
`data` thin pool used as `local-lvm`).

| Host | Model | Boot mode | Disk | `root` | `swap` | `local-lvm` (thin) |
|---|---|---|---|---|---|---|
| `srv01` | Dell OptiPlex 3050 Micro | Legacy BIOS | NVMe 476.9 GB | 96 GiB | 8 GiB | ~348 GiB |
| `srv02` | Dell OptiPlex 3070 Micro | UEFI + Secure Boot | SATA SSD 894.3 GB | 96 GiB | 8 GiB | ~758 GiB |

State collected on each node:

```bash
hostname -f
pveversion
uname -r
[ -d /sys/firmware/efi ] && echo UEFI || echo Legacy
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
pvesm status
```

```
Name             Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
local             dir     active        98497780         5564636        87883596    5.65%
local-lvm     lvmthin     active       364797952               0       364797952    0.00%
```
*(srv01 — before any project VM was created)*

### 3.2 Network

A single Linux bridge (`vmbr0`) on the onboard NIC. Same layout on both nodes, only the address changes.

```
auto vmbr0
iface vmbr0 inet static
	address 192.168.2.170/24
	gateway 192.168.2.1
	bridge-ports nic0
	bridge-stp off
	bridge-fd 0
```

DNS on the hosts currently points to a public resolver. It will move to Technitium (`tools-01`)
once that VM exists, with the router as secondary.

### 3.3 Cluster

The cluster `CL-QBC` was created on `srv01` and `srv02` was joined to it. CLI equivalent:

```bash
# on srv01
pvecm create CL-QBC

# on srv02
pvecm add 192.168.2.170
```

Corosync uses the IP addresses of the nodes as ring addresses:

```bash
grep -E "name:|ring0_addr" /etc/pve/corosync.conf
```

```
    name: srv01
    ring0_addr: 192.168.2.170
    name: srv02
    ring0_addr: 192.168.2.171
  cluster_name: CL-QBC
```

### 3.4 Package repositories

The enterprise repositories require a subscription, so they are disabled and the
`pve-no-subscription` repository is used (acceptable for a lab, not for production).
Proxmox VE 9 (Debian 13 "trixie") uses the deb822 `.sources` format.

```bash
ls /etc/apt/sources.list.d/
```

```
ceph.sources.disabled  debian.sources  proxmox.sources  pve-enterprise.sources.disabled
```

`/etc/apt/sources.list.d/proxmox.sources`:

```
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: true
```

### 3.5 Aligning the domain

The nodes had been installed with the domain `mello.local`. They were aligned with the project domain
`rafaelmellonh.com.br` (see [Issues found](#5-issues-found-and-how-they-were-solved)).
Only the domain suffix changes; the node names (`srv01` / `srv02`) stay the same.

One node at a time:

```bash
cp /etc/hosts /etc/hosts.bak
cp /etc/resolv.conf /etc/resolv.conf.bak

sed -i 's/srv01\.mello\.local/srv01.rafaelmellonh.com.br/' /etc/hosts
sed -i 's/^search mello\.local/search rafaelmellonh.com.br/' /etc/resolv.conf

pvecm updatecerts --force
systemctl restart pveproxy
```

Validation:

```bash
hostname -f
openssl x509 -in /etc/pve/nodes/srv01/pve-ssl.pem -noout -ext subjectAltName
```

```
srv01.rafaelmellonh.com.br
X509v3 Subject Alternative Name:
    IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1, DNS:localhost, IP Address:192.168.2.170, DNS:srv01, DNS:srv01.rafaelmellonh.com.br
```

### 3.6 Updates

Both nodes are updated and rebooted **one at a time**, so the cluster is never without both nodes
for longer than a single reboot.

```bash
apt update && apt list --upgradable 2>/dev/null | cat
apt full-upgrade -y
```

Check whether a newer kernel was installed:

```bash
uname -r
proxmox-boot-tool kernel list
```

```
7.0.14-19-pve
Manually selected kernels:
None.

Automatically selected kernels:
7.0.14-19-pve
7.0.14-28-pve
```

The running kernel is older than the newest installed one, so a reboot is needed:

1. Reboot `srv01` (no VMs) and wait until `pvecm status` shows `Nodes: 2` again.
2. On `srv02`, shut down the running VM from Proxmox (`qm shutdown <vmid>`), then reboot.

Result on both nodes: `pve-manager/9.2.21`, kernel `7.0.14-28-pve`.

### 3.7 Time synchronization

Proxmox uses `chrony` by default. Both nodes keep the system time zone in UTC.

```bash
timedatectl | grep -E "synchronized|Time zone"
chronyc tracking | grep -E "Reference|System time|Leap"
```

```
                Time zone: Etc/UTC (UTC, +0000)
System clock synchronized: yes
Reference ID    : 36271740 (64.ip-54-39-23.net)
System time     : 0.000012036 seconds fast of NTP time
Leap status     : Normal
```

### 3.8 Out-of-scope VM

`srv02` also hosts one personal VM (VMID 1001, 4 GiB), outside the scope of this project.
It is not managed by Terraform or Ansible and is shut down when the lab needs the extra memory.

## 4. Validation

| Check | Command | Expected | srv01 | srv02 |
|---|---|---|---|---|
| Proxmox version | `pveversion` | 9.2.x | ✅ 9.2.21 | ✅ 9.2.21 |
| Running kernel | `uname -r` | newest installed | ✅ 7.0.14-28-pve | ✅ 7.0.14-28-pve |
| FQDN | `hostname -f` | `<node>.rafaelmellonh.com.br` | ✅ | ✅ |
| Certificate SAN | `openssl x509 ... -ext subjectAltName` | new FQDN + IP | ✅ | ✅ |
| Repositories | `apt update` | no 401 from enterprise repo | ✅ | ✅ |
| Cluster | `pvecm status` | `Quorate: Yes`, `Nodes: 2` | ✅ | ✅ |
| Time | `timedatectl` | `synchronized: yes` | ✅ | ✅ |

## 5. Issues found and how they were solved

### Nodes installed with a different domain

**Symptom:** `hostname -f` returned `srv01.mello.local`, while the project uses `rafaelmellonh.com.br`.

**Analysis:** Changing a clustered node's *name* requires removing it from the cluster. Changing only
the *domain suffix* is safe here because:

- corosync uses IP addresses (`ring0_addr: 192.168.2.170`), not names;
- `/etc/hostname` contains only the short name (`srv01`), which is also the node directory in `/etc/pve/nodes/`;
- the domain appears only in `/etc/hosts`, `/etc/resolv.conf` and the node certificate.

**Solution:** updated `/etc/hosts` and `/etc/resolv.conf`, regenerated the certificates with
`pvecm updatecerts --force` and restarted `pveproxy`, one node at a time (section 3.5).
The cluster stayed quorate during the whole change.

### Checking the wrong certificate from the other node

**Symptom:** on `srv02`, the certificate check showed `srv01` names and IP.

**Cause:** the command still pointed to `/etc/pve/nodes/srv01/pve-ssl.pem`. `/etc/pve` is the
cluster file system (pmxcfs), replicated on every node, so the files of all nodes are visible from any of them.

**Solution:** use the path of the local node (`/etc/pve/nodes/srv02/pve-ssl.pem`).

### No `reboot-required` flag after a kernel update

**Symptom:** after `apt full-upgrade`, `/var/run/reboot-required` did not exist, but a new kernel had been installed.

**Solution:** compare the running kernel (`uname -r`) with the kernels listed by
`proxmox-boot-tool kernel list` instead of relying on that file.

### Quorum loss while one node reboots

**Symptom:** while one node is rebooting, the other one loses quorum (2 expected votes, 1 present).
Running VMs keep running, but `/etc/pve` becomes read-only: VMs cannot be started, stopped or changed.

**Solution:** expected behaviour in a two-node cluster. Nodes are rebooted one at a time and the
next step only starts after `pvecm status` shows both nodes again. A QDevice is planned (see below).

## 6. Future improvements

- QDevice to keep quorum when one of the two nodes is down
- SSH key authentication and `PermitRootLogin prohibit-password` (together with `mgmt-01` and Ansible)
- Hosts' DNS pointing to Technitium once `tools-01` exists
- Valid certificate for the web UI through ACME (DNS-01)
- Remove old kernels (`apt autoremove`), keeping the current and the previous one
- Dedicated Proxmox API user and token for Terraform — moved to [Phase 4](04-terraform.md)
