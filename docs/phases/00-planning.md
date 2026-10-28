# Phase 0 — Planning

## 1. Goal

Define everything that must be decided before touching the hardware: inventory of the physical hosts,
IP addressing, DNS, VM sizing, naming conventions and the main architecture decisions.
The output of this phase is the reference used by every following phase (Terraform, Ansible, Kubernetes).

## 2. Prerequisites

- Proxmox VE installed on both nodes and joined in the cluster `CL-QBC`
- Root access to both nodes (web UI and SSH)

## 3. Step by step

### 3.1 Architecture overview

![Architecture](../images/architecture.svg)

### 3.2 Hardware inventory

Data collected from the Proxmox web UI (*Node → Summary*) and from the storage status:

```bash
pvesm status
```

| Host | Model | IP | CPU | RAM | Boot mode | Root disk | VM storage (`local-lvm`, thin) |
|---|---|---|---|---|---|---|---|
| `srv01` | Dell OptiPlex 3050 Micro | 192.168.2.170 | Intel i5-7500T (4C/4T, Kaby Lake) | 15.5 GiB | Legacy BIOS | 94 GiB | ~348 GiB |
| `srv02` | Dell OptiPlex 3070 Micro | 192.168.2.171 | Intel i3-9100T (4C/4T, Coffee Lake) | 31.2 GiB | UEFI + Secure Boot | 94 GiB | ~758 GiB |

Software on both nodes:

- Proxmox VE 9 (`pve-manager` 9.2.x), kernel `7.0.14-19-pve`
- Repository: `pve-no-subscription` (acceptable for a lab, not for production)

> The "HD space" shown in the node summary is only the root filesystem (`local`).
> VM disks live in `local-lvm`, which is why `pvesm status` is needed to size them.

### 3.3 Operating system

All VMs run **Ubuntu 22.04.5 LTS (Jammy Jellyfish)**, from the cloud-init golden image.

```bash
cat /etc/os-release
```

```
PRETTY_NAME="Ubuntu 22.04.5 LTS"
VERSION_ID="22.04"
VERSION_CODENAME=jammy
```

### 3.4 IP addressing

Network `192.168.2.0/24`, gateway inherited from `vmbr0`.

| Range | Use |
|---|---|
| .170 – .179 | Physical hosts (room for future hardware) |
| .180 – .199 | Virtual machines |
| .200 – .209 | MetalLB pool |

| Address | Assigned to |
|---|---|
| 192.168.2.170 | srv01 |
| 192.168.2.171 | srv02 |
| 192.168.2.180 | mgmt-01 |
| 192.168.2.181 | zbx-01 |
| 192.168.2.182 | k8s-cp-01 |
| 192.168.2.183 | k8s-worker-01 |
| 192.168.2.184 | k8s-worker-02 |
| 192.168.2.185 | tools-01 (also the lab DNS server) |
| 192.168.2.186 – .199 | Reserved (future VMs) |
| 192.168.2.200 | Ingress NGINX (MetalLB) |
| 192.168.2.201 – .209 | Reserved (MetalLB) |

### 3.5 DNS

The lab uses **Technitium DNS Server** (Docker, on `tools-01`) as its authoritative DNS,
with a subdomain of a real domain instead of an invented TLD.

| Item | Value |
|---|---|
| Server | Technitium DNS Server — `192.168.2.185:53`, web console on port 5380 |
| Forward zone | `rafaelmellonh.com.br` (split-horizon: internal view of the public domain) |
| Reverse zone | `2.168.192.in-addr.arpa` (PTR created with each A record) |
| Forwarders | Router / public resolvers for everything outside the lab zones |
| Secondary DNS on clients | Router, so the home network keeps working if `tools-01` is down |

Planned records:

| Name | Type | Value |
|---|---|---|
| `srv01.rafaelmellonh.com.br` | A | 192.168.2.170 |
| `srv02.rafaelmellonh.com.br` | A | 192.168.2.171 |
| `mgmt-01.rafaelmellonh.com.br` | A | 192.168.2.180 |
| `zbx-01.rafaelmellonh.com.br` | A | 192.168.2.181 |
| `k8s-cp-01.rafaelmellonh.com.br` | A | 192.168.2.182 |
| `k8s-worker-01.rafaelmellonh.com.br` | A | 192.168.2.183 |
| `k8s-worker-02.rafaelmellonh.com.br` | A | 192.168.2.184 |
| `tools-01.rafaelmellonh.com.br` | A | 192.168.2.185 |
| `netbox.rafaelmellonh.com.br` | CNAME | tools-01 |
| `dns.rafaelmellonh.com.br` | CNAME | tools-01 |
| `*.apps.rafaelmellonh.com.br` | A | 192.168.2.200 (Ingress) |

Applications in Kubernetes (Grafana, Argo CD, Podinfo, Online Boutique) are published under
`*.apps.rafaelmellonh.com.br`, so a single wildcard record points them all to the Ingress.

> The internal zone takes over the whole domain inside the home network. Any record that exists
> in the public DNS (website, MX, TXT) must also be created in Technitium, otherwise it stops
> resolving for clients on the LAN.

> On Ubuntu 22.04, `systemd-resolved` listens on port 53. Its stub listener must be disabled
> (`DNSStubListener=no` in `/etc/systemd/resolved.conf`) before the Technitium container starts.

### 3.6 Virtual machines

| VM | Node | IP | vCPU | RAM | Disk | Role |
|---|---|---|---|---|---|---|
| mgmt-01 | srv01 | .180 | 2 | 2 GiB | 30 GB | GitLab runner, Terraform, Ansible |
| zbx-01 | srv01 | .181 | 2 | 4 GiB | 50 GB | Zabbix 7 LTS |
| k8s-cp-01 | srv01 | .182 | 2 | 4 GiB | 40 GB | Kubernetes control plane |
| k8s-worker-01 | srv02 | .183 | 4 | 10 GiB | 100 GB | Kubernetes worker |
| k8s-worker-02 | srv02 | .184 | 4 | 10 GiB | 100 GB | Kubernetes worker |
| tools-01 | srv02 | .185 | 2 | 6 GiB | 50 GB | Internal tools in Docker (NetBox, Technitium DNS) |

Prometheus, Grafana, Argo CD and the applications run inside the Kubernetes cluster, not in dedicated VMs.

### 3.7 Resource budget

About 2–3 GiB of RAM is kept free on each node for Proxmox itself.

| Node | Usable RAM | Allocated RAM | VM disk allocated | VM storage |
|---|---|---|---|---|
| srv01 | ~13 GiB | 10 GiB | 120 GB | ~348 GiB |
| srv02 | ~28 GiB | 26 GiB | 250 GB | ~758 GiB |

- vCPU overcommit is accepted (lab workload).
- Workers get 10 GiB each so that Online Boutique (with its load generator) and the monitoring stack fit together.
- `local-lvm` is thin-provisioned: a VM only consumes the space it actually writes.

### 3.8 Conventions

- **VM names:** `<role>-<nn>` (e.g. `zbx-01`, `k8s-worker-02`).
- **Node names:** keep the existing `srv01` / `srv02` (renaming a clustered Proxmox node requires removing it from the cluster).
- **FQDN:** `<name>.rafaelmellonh.com.br`; Kubernetes applications under `*.apps.rafaelmellonh.com.br`.
- **VM CPU type:** `x86-64-v3` on every VM. The nodes have different CPU generations, and type `host` would break migration between them.

### 3.9 Architecture decisions

Recorded as ADRs in [docs/adr](../adr):

| Decision | Reason |
|---|---|
| GitLab.com as primary repository, mirrored to GitHub | No Git server to maintain at home; GitHub mirror for visibility |
| Golden image built directly on Proxmox (no Packer) | Simpler for two nodes; VMs created from it later by Terraform |
| Ubuntu 22.04 LTS for all VMs | Existing golden image template; LTS release supported by kubeadm, Zabbix and Docker |
| Kubernetes with kubeadm | Same tooling as the CKA exam; full control of the cluster |
| NetBox on `tools-01` with Docker Compose (netbox-docker) | Fast to install, easy to upgrade and to rebuild; must exist before Terraform and the cluster |
| Technitium DNS Server on `tools-01` (Docker) | Full authoritative DNS with forward and reverse zones and a web console, similar to Windows DNS; has an API for automation |
| `rafaelmellonh.com.br` as lab domain (split-horizon) | Real domain owned by the author instead of an invented TLD; short names; ready for valid TLS certificates later |
| MetalLB in L2 mode | The home router does not support BGP; one IP is enough behind the Ingress |

## 4. Future improvements

- QDevice to keep quorum when one of the two nodes is down
- Shared storage between the nodes
- NetBox as the source of truth: Terraform and Ansible reading hosts and IPs from it
- DNS records created automatically through the Technitium API
- Public DNS with API (Cloudflare or Azure DNS) for valid Let's Encrypt certificates via cert-manager (DNS-01)
