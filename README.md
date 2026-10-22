# homelab-platform

> From bare metal to a fully automated, observable platform — and then to the cloud — all as code.


## Where the project lives

| | Repository | Content |
|---|---|---|
| **Primary** | [GitLab](https://gitlab.com/rmellonh/homelab-platform) | Code, CI/CD pipelines, merge requests, issues and registry |
| **Mirror** | [GitHub](https://github.com/rafamellonh/homelab-platform) | Automatic copy of the code and documentation (read-only) |

Development happens on GitLab. Every push is automatically replicated to GitHub through a *push mirror*.
To see pipelines running, open issues or follow merge requests, visit GitLab.
All documentation, including the issues found and how they were solved, lives in the repository itself and is available on both.

---

## About

This project documents, step by step, the build of a complete platform on two mini PCs at home:
starting from a bare-metal Proxmox install, through infrastructure as code, configuration management,
Kubernetes, CI/CD, GitOps and observability — delivering and operating real applications —
and finally migrating the workloads to a public cloud using the same code.

The goal is to apply and demonstrate SRE/DevOps skills on real infrastructure, not in a sandbox.

**Journey:** bare metal → automation → platform → operations → cloud

## Motivation

I have experience with most of the tools in this project, but my current job doesn't put me
in daily contact with all of them. This project is how I keep them in practice and up to date
while developing the skills I don't yet use day to day.

| Goal | Areas |
|---|---|
| **Practice and stay current** | Linux, virtualization (Proxmox), Ansible, Terraform, Kubernetes, Zabbix, cloud |
| **Learn and develop** | CI/CD, GitOps (Argo CD), cloud-native observability (Prometheus and Grafana), SRE practices |

That's why the documentation records not only what worked, but also the mistakes, the questions
and the decisions made along the way.

## Architecture

<!-- Uncomment when the diagram is ready:
![Architecture](docs/images/architecture.png)
-->

```
GitLab.com (primary) ──push mirror──► GitHub (mirror)
   │
   │ CI/CD jobs (local runner)
   ▼
┌──────────────────── Proxmox VE cluster ────────────────────┐
│  pve-01 (16 GB)                   pve-02 (32 GB)            │
│  ├── mgmt-01   runner/TF/Ansible  ├── k8s-worker-01         │
│  ├── zbx-01    Zabbix             └── k8s-worker-02         │
│  └── k8s-cp-01                                              │
└─────────────────────────────────────────────────────────────┘

Kubernetes: MetalLB · Ingress NGINX · Argo CD
            Prometheus · Alertmanager · Grafana
            Podinfo · Online Boutique
```

## Tech stack

| Layer | Tools |
|---|---|
| Virtualization | Proxmox VE 9 |
| Operating system | Ubuntu 24.04 LTS (cloud-init golden image) |
| Provisioning | Terraform (`bpg/proxmox`) |
| Configuration | Ansible |
| Containers & orchestration | Kubernetes (kubeadm), containerd |
| Repository & CI/CD | GitLab.com + GitLab CI (local runner), mirrored to GitHub |
| Registry | GitLab Container Registry |
| GitOps | Argo CD, Kustomize |
| Monitoring | Zabbix 7 LTS, Prometheus, Alertmanager, Grafana |
| Applications | Podinfo, Online Boutique |
| Cloud | AWS or Azure (to be decided) |

## Hardware

| Host | Role | RAM |
|---|---|---|
| Dell mini PC #1 | Proxmox node `pve-01` | 16 GB |
| Dell mini PC #2 | Proxmox node `pve-02` | 32 GB |

## Applications

- **[Podinfo](https://github.com/stefanprodan/podinfo)** — used to demonstrate the full delivery path:
  build, security scan, push to the registry and GitOps deployment.
- **[Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)** — an 11-microservice application
  with a built-in load generator, used for operations, monitoring and failure scenarios.

## Roadmap

| # | Phase | Status | Docs |
|---|---|---|---|
| 0 | Planning | ⏳ | [00-planning](docs/00-planning.md) |
| 1 | Proxmox installation & cluster | ⏳ | [01-proxmox](docs/01-proxmox.md) |
| 2 | Golden image | ⏳ | [02-golden-image](docs/02-golden-image.md) |
| 3 | First VM (manual) | ⏳ | [03-first-vm](docs/03-first-vm.md) |
| 4 | Provisioning with Terraform | ⏳ | [04-terraform](docs/04-terraform.md) |
| 5 | Configuration with Ansible | ⏳ | [05-ansible](docs/05-ansible.md) |
| 6 | Infrastructure monitoring (Zabbix) | ⏳ | [06-zabbix](docs/06-zabbix.md) |
| 7 | Kubernetes | ⏳ | [07-kubernetes](docs/07-kubernetes.md) |
| 8 | CI/CD | ⏳ | [08-cicd](docs/08-cicd.md) |
| 9 | GitOps | ⏳ | [09-gitops](docs/09-gitops.md) |
| 10 | Observability | ⏳ | [10-observability](docs/10-observability.md) |
| 11 | Online Boutique | ⏳ | [11-application](docs/11-application.md) |
| 12 | SRE: SLOs & failure scenarios | ⏳ | [12-sre-scenarios](docs/12-sre-scenarios.md) |
| 13 | Rebuild from scratch | ⏳ | [13-rebuild](docs/13-rebuild.md) |
| 14 | Cloud foundation | ⏳ | [14-cloud-foundation](docs/14-cloud-foundation.md) |
| 15 | Lift-and-shift | ⏳ | [15-lift-and-shift](docs/15-lift-and-shift.md) |
| 16 | Managed Kubernetes | ⏳ | [16-managed-k8s](docs/16-managed-k8s.md) |
| 17 | Hybrid & cutover | ⏳ | [17-cutover](docs/17-cutover.md) |
| 18 | Cost report & teardown | ⏳ | [18-cost-and-teardown](docs/18-cost-and-teardown.md) |

✅ Done · 🚧 In progress · ⏳ Planned

## Repository structure

```
homelab-platform/
├── docs/            # phase docs, troubleshooting, ADRs and postmortems
├── scripts/         # golden image creation
├── terraform/       # VM provisioning (lab and cloud environments)
├── ansible/         # configuration management (roles and playbooks)
├── kubernetes/      # GitOps manifests managed by Argo CD (Kustomize)
└── .gitlab-ci.yml   # CI/CD pipeline (runs on GitLab)
```

## Documentation

Every phase is documented with the same structure:

1. Goal
2. Prerequisites
3. Step by step
4. Validation
5. Issues found and how they were solved
6. Future improvements

- **Issues and solutions (summary of all phases):** [docs/troubleshooting.md](docs/troubleshooting.md)
- **Architecture decisions:** [docs/adr](docs/adr)
- **Postmortems:** [docs/postmortems](docs/postmortems)

## Principles

- **Everything as code** — infrastructure, configuration and deployments are versioned in Git.
- **Reproducible** — the whole platform can be destroyed and rebuilt from this repository.
- **Portable** — generic Terraform modules, provider-agnostic Ansible roles and Kustomize overlays,
  so the same code can move to the cloud.
- **Secure by default** — no secrets in the repository; protected GitLab variables and Ansible Vault;
  fork pipelines don't use the local runner; deployments only from `main`, with manual approval.
- **Observable** — from the physical host temperature to application latency.
- **Transparent** — mistakes, questions and decisions are recorded in the documentation, not just the final result.

## Known limitations

- Local storage on each Proxmox node (one golden image template per node). Shared storage is planned.
- Single control plane node (no Kubernetes high availability).
- Not exposed to the internet.

## Author

**Rafael** — Systems / Infrastructure Administrator on the path to SRE/DevOps.

[LinkedIn](https://www.linkedin.com/in/rafaelmellobr) · [GitLab](https://gitlab.com/rmellonh) · [GitHub](https://github.com/rafamellonh)
