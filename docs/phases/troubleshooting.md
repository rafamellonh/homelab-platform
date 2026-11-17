# Troubleshooting

Summary of the issues found in every phase. The full analysis (symptom, cause and solution) is in
section 5 of each phase document.

## Phase 1 — Proxmox installation & cluster

[Full details](01-proxmox.md#5-issues-found-and-how-they-were-solved)

| Issue | Cause | Solution |
|---|---|---|
| Nodes installed with the domain `mello.local` | Wrong domain at install time | Changed only the domain suffix (`/etc/hosts`, `/etc/resolv.conf`) and ran `pvecm updatecerts --force`, one node at a time |
| Certificate check on `srv02` showed `srv01` names | `/etc/pve` is replicated on every node; the path still pointed to `srv01` | Use the path of the local node (`/etc/pve/nodes/<node>/pve-ssl.pem`) |
| No `reboot-required` flag after a kernel update | Proxmox does not always create the file | Compare `uname -r` with `proxmox-boot-tool kernel list` |
| Quorum loss while one node reboots | Two-node cluster: one vote out of two | Reboot one node at a time and wait for `pvecm status`; QDevice planned |

## Phase 2 — Golden image

[Full details](02-golden-image.md#5-issues-found-and-how-they-were-solved)

| Issue | Cause | Solution |
|---|---|---|
| Installer failed in `curtin command in-target` | Corrupted ISO | Downloaded again; verify with `sha256sum -c SHA256SUMS` |
| LVM with a 10 GB `/` | LVM enabled by default in the installer | Unchecked *Set up this disk as an LVM group* |
| No network after the clean-up | Network configuration removed on purpose | Temporary DHCP from the console; clean-up as the last step before shutdown |
| SSH refused after removing the host keys | `sshd` does not start without host keys | `ssh-keygen -A` while working; removed again in the final clean-up |
| `qm set` aborted, no cloud-init option applied | Missing SSH key file; `qm set` validates all options first | Copied the key to the node and ran `qm set` again |
| Interface `eth0` instead of `ens18` | Cloud-init matches the NIC by MAC and renames it | Expected; `eth0` is used in Ansible and monitoring |
| Cannot clone a template to another node | `--target` requires shared storage | Full clone on the same node, offline migration, then `qm template` |

## Phase 3 — First VM: DNS and NetBox

[Full details](03-first-vm.md#5-issues-found-and-how-they-were-solved)

| Issue | Cause | Solution |
|---|---|---|
| Docker could not pull images (`127.0.0.53:53 connection refused`) | Docker read the old stub resolver at start | `systemctl restart docker`; disable the stub listener before installing Docker |
| PTR records in the forward zone | Record type left on PTR, name/value inverted | Only A records, with *Add reverse (PTR) record* |
| Wrong PTR for `.185`, invalid PTR for `.200` | PTR option checked on the `dns` and `*.apps` records | One PTR per IP, never for a wildcard |
| Technitium console not reachable over HTTPS | HTTPS not enabled, no certificate | Enabled HTTPS with a self-signed certificate |
| NetBox `unhealthy` on the first start | Migrations longer than the default `start_period` | `start_period: 300s` in the override |
| NetBox down after a reboot of `tools-01` | netbox-docker sets no restart policy | `restart: unless-stopped` on every service in the override |
| YAML error in the override | Wrong indentation | Spaces only; `docker compose config` before `up` |
| Default secrets in netbox-docker | Example values in `env/*.env` | All replaced before the first start |
| NetBox import: `Object not found` | Related objects did not exist yet | Create objects in dependency order |
| Cluster named after its type | *Name* and *Type* confused | Name `CL-QBC`, type `Proxmox VE` |
| No *VM role* option | Not present in NetBox 4.7 | Not needed; roles apply to devices and VMs |
| VM platform not listed | Platform did not exist | Created `Ubuntu 24.04 LTS` |
| Physical NIC rejected as child of the bridge | *Parent interface* is for subinterfaces | Used the *Bridge* field |
| New SSH host key after changing the nameserver | Cloud-init runs again as a new instance | Expected; `ssh-keygen -R` and accept the new key |

## Phase 4 — Provisioning with Terraform

[Full details](04-terraform.md#5-issues-found-and-how-they-were-solved)

| Issue | Cause | Solution |
|---|---|---|
| `event not found` when exporting the token | `!` triggers history expansion in double quotes | Single quotes around the fixed part of the token |
| `Argument names must not be quoted` | `address =` lost while editing | Restored the argument; `terraform validate` catches it |
| `Reference to undeclared input variable` | Typo in the variable name | Renamed to `network` |
| `Blocks of type "dns" are not expected here` | Extra `}` closed `initialization` | Moved the blocks back; `terraform fmt` shows it through indentation |
| `Unable to create Proxmox VE API credentials` | Environment variable only exists in the shell that exported it | `source ~/.config/homelab/secrets.env` in every new terminal |

## Phase 5 — Configuration with Ansible

[Full details](05-ansible.md#5-issues-found-and-how-they-were-solved)

| Issue | Cause | Solution |
|---|---|---|
| `Host key verification failed` | Empty `known_hosts` on mgmt-01 | `ssh-keyscan` with the inventory names, instead of disabling `host_key_checking` |
| `ansible-lint`: `No module named 'ansible.parsing.yaml.constructor'` | Ubuntu package older than the PPA `ansible-core` | Installed with `pipx`, as the normal user (not `sudo`) |
| `couldn't resolve module/action 'community.general.timezone'` | The `pipx` ansible-lint does not see the bundled collections | `requirements.yml` + `ansible-galaxy collection install --force` |
| `validate` failed: `/usr/bin/sshd` not found | Typo; `sshd` is in `/usr/sbin` | Fixed the path; nothing was written |
| `Module br_netfiler not found` | Typo in `defaults/main.yml` | Fixed the variable |
| Reboot hung, internal names not resolving | `systemd-resolved` stuck on `8.8.8.8` while `tools-01` rebooted | Restarted `systemd-resolved`; reboot `tools-01` separately |
| `SystemdCgroup` not applied, with `changed=0` | containerd 2.2 config (version 3) has no `SystemdCgroup` line | `lineinfile` with `insertafter`; validate with `containerd config dump` |
| `INJECT_FACTS_AS_VARS` deprecation warning | Facts as top-level variables are being removed | `ansible_facts['swaptotal_mb']` |
| `git push` rejected | Commits pushed from another machine | `git config pull.rebase true`, then `git pull` |

## Lessons across phases

- **Validate before applying:** `sha256sum -c`, `docker compose config`, `terraform validate`, `ansible-lint`
  and the `validate` option of Ansible caught errors before they reached a running system.
- **Idempotency does not prove correctness:** check the result itself (`sshd -T`, `containerd config dump`),
  not only `changed=0`.
- **Services read their configuration at start:** Docker, containers and `systemd-resolved` keep the old
  DNS settings until they are restarted.
- **The lab DNS is a single point of failure:** `8.8.8.8` as secondary resolves external names only, and
  clients can stay on it after `tools-01` comes back. A second DNS server is planned.
- **One node at a time:** in a two-node cluster, every reboot or change on the Proxmox nodes is done on one
  node and checked before moving to the other.
