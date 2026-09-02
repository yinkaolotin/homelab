# Homelab Architecture

A 3-VM [k3s](https://k3s.io/) cluster provisioned by Puppet, with everything on top
managed by Argo CD via GitOps. This document is the map for re-orienting after time away.

## Layers at a glance

| Layer | Tooling | What it does |
|-------|---------|--------------|
| 1. VMs + OS + Kubernetes | Puppet (masterless) | Turns 3 libvirt/KVM VMs into a k3s cluster |
| 2. GitOps | Argo CD app-of-apps | Syncs all cluster add-ons from this repo |
| 3. Data + backup/restore | CloudNativePG, Barman, MinIO, Velero | Shared Postgres and its backup verification chain |
| 4. Workload | `tiny` Helm chart | The application itself |

---

## Layer 1 — VMs + OS + Kubernetes (Puppet)

`puppet/apply.sh` runs `puppet apply manifests/site.pp` **locally on each node** — there is
no Puppet server. Nodes are libvirt/KVM VMs on the default `192.168.122.0/24` NAT network
(`qemu-guest-agent` installed; get the master IP with `virsh domifaddr master`).

### Nodes (`puppet/manifests/site.pp`)

All three share the hardcoded cluster token `yinkaolotin`.

| Node | Classes | Role |
|------|---------|------|
| `master` | `base`, `k8s_master`, `git_ssh` | k3s **server**, API at `https://192.168.122.56:6443` |
| `worker-1` | `base`, `k8s_worker`, `git_ssh` | k3s **agent** |
| `worker-2` | `base`, `k8s_worker`, `git_ssh` | k3s **agent** |

`node default` fails loudly if a VM's certname matches no block.

### Classes (`puppet/modules/homelab/manifests/`)

- **`base.pp`** — common packages (curl, vim, git, htop, net-tools, qemu-guest-agent,
  ca-certificates); writes `~/.puppet/etc/puppet.conf` with `certname = hostname`.
- **`k8s_master.pp`** — writes `/etc/rancher/k3s/config.yaml` with `disable: [traefik, servicelb]`,
  installs k3s from `get.k3s.io` as `server`, waits for the API, copies kubeconfig to
  `/root/.kube/config` and `/home/yinkaolotin/.kube/config`, then replaces the k3s `kubectl`
  symlink with a standalone `kubectl v1.35.5` binary.
- **`k8s_worker.pp`** — points `config.yaml` at the master URL + token, installs k3s as `agent`.
- **`git_ssh.pp`** — SSH `config` + `known_hosts` for `github.com` using deploy key
  `github_homelab_ed25519`, so the node can clone this repo.
- **`argocd.pp`** — **empty placeholder.** Argo CD is bootstrapped by hand today
  (see "Bootstrap" below); automating it here is a TODO.

### Consequences of `disable: [traefik, servicelb]`

- No default ingress controller — we bring our own (ingress-nginx).
- No `LoadBalancer` Service support — ingress-nginx is exposed as **NodePort**, reached at
  `<node-ip>:<nodeport>`.

### `puppet/modules/upstream/`

Vendored third-party Puppet modules (`inifile`, `stdlib`) — not our code.

---

## Layer 2 — GitOps (Argo CD app-of-apps)

**`infra/argocd/root.yaml`** is the root `Application`. It watches
`git@github.com:yinkaolotin/homelab.git` path `infra/argocd/apps/` with
`automated: { prune: true, selfHeal: true }`. Every file in that directory is a child
`Application`.

### Two child-app patterns

1. **Helm + values-from-git** (multi-source): an upstream chart repo **plus** this repo
   referenced as `ref: values`, supplying `$values/infra/.../values.yaml`.
2. **Raw manifests**: a `path:` pointing at a directory of plain YAML.

All children use auto-sync, prune, self-heal, and `CreateNamespace=true`.

### The apps

| App | Chart / source | Namespace | Purpose / notes |
|-----|----------------|-----------|-----------------|
| `cert-manager` | jetstack `v1.16.3` | `cert-manager` | TLS issuance. **Installed but not wired** — no ClusterIssuer/Certificate in the repo yet |
| `ingress-nginx` | `4.12.1` | `ingress-nginx` | Cluster HTTP entrypoint. `service.type: NodePort`. metrics + ServiceMonitor enabled |
| `kube-prometheus` | kube-prometheus-stack `85.3.0` | `monitoring` | Prometheus (3d retention, 30s scrape), Grafana (`admin`/`admin`), Alertmanager, kube-state-metrics, node-exporter. `serviceMonitorSelectorNilUsesHelmValues: false` → discovers **all** ServiceMonitors/PodMonitors cluster-wide |
| `cnpg` | cloudnative-pg `0.24.0` | `cnpg-system` | Postgres operator. In-place instance-manager updates enabled. ServerSideApply |
| `cnpg-barman-plugin` | plugin-barman-cloud `0.6.0` | `cnpg-system` | Sidecar Barman Cloud plugin — WAL archiving + base backups to S3. Modern replacement for CNPG's deprecated in-tree `barmanObjectStore` |
| `minio` | minio `5.4.0` | `minio` | Standalone S3-compatible object store. 10Gi PVC. Creds `admin`/`yinkaolotin`. Backup target for everything below |
| `velero` | velero `12.0.1` | `velero` | Cluster + PV backups. AWS plugin `v1.12.2` → in-cluster MinIO bucket `velero-backups`. `uploaderType: kopia`, `defaultVolumesToFsBackup: true` (node-agent DaemonSet does filesystem-level PV backups). `publicUrl: http://127.0.0.1:9000` for local CLI via port-forward |
| `shared-postgres-dev` | raw manifests | `shared-postgres-dev` | The shared dev database — see Layer 3 |
| `shared-pitr` | raw manifests | `shared-pitr` | Point-in-time-recovery test cluster — see Layer 3 |
| `restore-test-cluster` | raw manifests | `shared-postgres-restore` | Restore-to-latest verification cluster — see Layer 3 |
| `tiny-dev` | local chart `services/tiny` | `tiny-dev` | The application — see Layer 4 |

### Bootstrap (manual, until `argocd.pp` is filled in)

1. `puppet/apply.sh` on each VM → k3s cluster forms, kubeconfig lands on the master.
2. On the cluster: `helm install` Argo CD into the `argocd` namespace.
3. Register this repo's SSH deploy key as an Argo CD repo credential.
4. `kubectl apply -f infra/argocd/root.yaml` → root app pulls in everything else.

---

## Layer 3 — Postgres + backup/restore chain

### `infra/storage/postgres/shared-dev/` (app `shared-postgres-dev`)

- **`cluster.yaml`** — `Cluster shared-postgres`: 1 instance, PG 16, 5Gi storage.
  `bootstrap.initdb` creates database `tiny` owned by role `tiny`. The barman-cloud plugin
  is registered with `isWALArchiver: true` targeting `ObjectStore minio-store`.
  PodMonitor enabled.
- **`object-store.yaml`** — `ObjectStore minio-store` → `s3://cnpg-backups/shared-postgres-dev`
  on the in-cluster MinIO, credentials from secret `minio-backup-creds`, gzip WAL + data.
- **`scheduled-backup.yaml`** — `ScheduledBackup shared-postgres-daily`, cron
  `0 0 2 * * *` (02:00 daily), method `plugin`.
- **`manual-backup.yaml`** — one-off `Backup shared-postgres-manual-001`.
- **`minio-secret.yaml`** / **`namespace.yaml`**.

### `infra/storage/postgres/shared-pitr/` (app `shared-pitr`)

`Cluster shared-pitr` bootstraps via `recovery` from external cluster
`shared-postgres-backup` (same S3 path, `serverName: shared-postgres`) with
`recoveryTarget.targetTime: "2026-05-31 08:41:32.188148+00"`. Proves **point-in-time**
recovery works. Has its own ObjectStore + `minio-pitr-creds` secret.

### `infra/storage/postgres/restore-test/` (app `restore-test-cluster`)

`Cluster shared-postgres-restore` — same recovery source, **no** `recoveryTarget` → restores
to latest. Proves a plain restore works. Own ObjectStore + `minio-restore-creds` secret.

### Two independent backup mechanisms

1. **CNPG + Barman** → continuous WAL + nightly base backups of `shared-postgres` → MinIO
   `cnpg-backups`. Validated by the `shared-pitr` and `restore-test` clusters.
2. **Velero + Kopia** → whole-cluster resource manifests + PV filesystem data → MinIO
   `velero-backups`.

---

## Layer 4 — The `tiny` app

Hand-written Helm chart in `services/tiny/charts/tiny` (scaffolded from `helm create` — the
chart's own `values.yaml` is still boilerplate; real config is `services/tiny/values/dev.yaml`,
and `values/prod.yaml` is empty).

- Image `ghcr.io/yinkaolotin/tiny:0.2.0`, pulled with `ghcr-pull-secret`. Binary `/app/tiny`,
  has a `migrate` subcommand.
- **`deployment.yaml`** — 1 replica, container port 8080. Env from the `env` map
  (`STORAGE_BACKEND: postgres`, `DATA_DIR: /data`, etc.) plus `DB_HOST/PORT/NAME/USER` and
  `DB_PASSWORD` from secret `tiny-postgres-credentials` (key `password`). Probes `/ready`
  and `/health`. Mounts PVC `tiny-data` at `/data`.
- **`migration-job.yaml`** — Helm `pre-install,pre-upgrade` hook (weight `-10`) running
  `/app/tiny migrate` before each rollout.
- **`service.yaml`** — ClusterIP on port 80.
- **`pvc.yaml`** — 1Gi, storageClass `local-path` (k3s local-path provisioner).
- **`servicemonitor.yaml`** — scrapes `/metrics`, 30s, label `release: kube-prometheus`.
- **`prometheusrule.yaml`** — alerts `TinyDown` (`up == 0` for 2m) and `TinyPodRestarting`.
- **Ingress** (from `dev.yaml`) — host `tiny.local`, class `nginx`. Reach it with
  `curl -H "Host: tiny.local" <node-ip>:<nodeport>` (dev.yaml comments an example port `32080`).
- **DB target** — `shared-postgres-rw.shared-postgres-dev.svc.cluster.local:5432`,
  database/user `tiny`.

---

## Request and data flow

```
  operator ─ puppet apply (per VM) ──► k3s: master(192.168.122.56) + worker-1 + worker-2
  operator ─ helm install argo-cd + kubectl apply root.yaml ──► Argo CD

  Argo CD ──(pull SSH repo + upstream Helm charts)──► syncs infra/argocd/apps/*
       │
       ├─ ingress-nginx (NodePort)   ├─ kube-prometheus        ├─ cert-manager (idle)
       ├─ cnpg + barman plugin       ├─ minio                  ├─ velero (+ node-agent)
       └─ shared-postgres-dev / shared-pitr / restore-test / tiny-dev

  client ─► <node-ip>:<nodeport> ─► ingress-nginx ─► Service tiny ─► tiny pods
                                                                        │  (DB_*)
                                                                        ▼
                                     shared-postgres-rw (CNPG, shared-postgres-dev ns)
                                                                        │ WAL + base backups (Barman plugin)
                                                                        ▼
                                     MinIO (minio ns)  bucket cnpg-backups/  ◄─ ScheduledBackup 02:00
                                          ▲    │
            Velero (kopia FS backups) ────┘    └──► shared-pitr / restore-test clusters read back to verify

  Prometheus ──(ServiceMonitor/PodMonitor)──► ingress-nginx, CNPG, tiny, node-exporter, kube-state-metrics
       └─► Grafana (dashboards) + Alertmanager (TinyDown, TinyPodRestarting, …)
```

---

## In-progress state / known gaps

- **Argo CD bootstrap is manual** — `homelab::argocd` is an empty placeholder.
- **cert-manager does nothing yet** — no ClusterIssuer; all ingress is plain HTTP via
  `tiny.local` in `/etc/hosts`.
- **Secrets are plaintext in git** — MinIO/Postgres creds all `yinkaolotin`, Grafana
  `admin`/`admin`, k3s token in `site.pp` (which itself notes "move this to Hiera/secrets").
  No SOPS / sealed-secrets.
- **`tiny-postgres-credentials` secret and the `tiny` role's password are not in the repo** —
  created out-of-band. CNPG's `initdb` creates the role; the password wiring is external.
- **Single environment** — `services/tiny/values/prod.yaml` is empty; only `dev` exists.
- **Master IP `192.168.122.56` is hardcoded** in `site.pp` and must match
  `virsh domifaddr master`.
- Repo `.gitignore` is a stray Rust/Cargo template.

---

## Repo layout

```
infra/
  argocd/
    root.yaml              # app-of-apps root Application
    apps/*.yaml            # one Argo Application per add-on
  networking/ingress-nginx/values.yaml
  monitoring/kube-prometheus/values.yaml
  security/cert-manager/values.yaml
  storage/
    cnpg/values.yaml
    cnpg-barman-plugin/values.yaml
    postgres/
      shared-dev/          # shared-postgres Cluster + backups
      shared-pitr/         # PITR test cluster
      restore-test/        # restore-to-latest test cluster
  backup/
    minio/values.yaml
    velero/values.yaml
puppet/
  apply.sh                 # sudo puppet apply, masterless
  manifests/site.pp        # node definitions
  modules/homelab/         # base, k8s_master, k8s_worker, git_ssh, argocd(stub)
  modules/upstream/        # vendored inifile + stdlib
services/tiny/
  charts/tiny/             # hand-written Helm chart
  values/dev.yaml          # real config
  values/prod.yaml         # empty
```
