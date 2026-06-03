# Senior DevOps Candidate Task

Provision a local Kubernetes cluster using Terraform, deploy three web applications via a
GitOps pipeline backed by ArgoCD, expose them through Traefik with distinct path-based
routes, and automate everything with a GitHub Actions CI/CD pipeline.

---

## Architecture

Traffic enters the host on port 80/443, passes through the k3d load balancer into Traefik,
which routes by path prefix to each app. ArgoCD watches the git repo and reconciles any
change to `gitops/apps/` automatically. Adding a new app requires only two files and a
git push — no Terraform changes.

```
┌─────────────────────────────────────────────────────────────────────┐
│  HOST (macOS / CI runner)                                           │
│                                                                     │
│  localhost:80 / localhost:443                                       │
│         │                                                           │
│  ┌──────▼──────────────────────────────────────────────────────┐    │
│  │  k3d cluster  (surf-cluster)                                │    │
│  │                                                             │    │
│  │  ┌─────────────────────────┐                                │    │
│  │  │  k3d Load Balancer      │  ← Docker port-maps 80/443     │    │
│  │  └────────────┬────────────┘                                │    │
│  │               │                                             │    │
│  │  ┌────────────▼────────────────────────────────────────┐    │    │
│  │  │  Traefik  (Ingress / API Gateway)                   │    │    │
│  │  │  IngressRoute CRDs + strip-prefix Middleware        │    │    │
│  │  │                                                     │    │    │
│  │  │  /python-app ──► python-app-svc (8080)              │    │    │
│  │  │  /echo-app   ──► echo-app-svc   (8080)              │    │    │
│  │  │  /podinfo    ──► podinfo-svc    (9898)              │    │    │
│  │  └─────────────────────────────────────────────────────┘    │    │
│  │                                                             │    │
│  │  ┌─────────────────────────────────────────────────────┐    │    │
│  │  │  ArgoCD  (App-of-Apps)                              │    │    │
│  │  │                                                     │    │    │
│  │  │  root-app  ──  watches gitops/apps/ in git          │    │    │
│  │  │    ├── python-app/Application.yaml ──► python-app   │    │    │
│  │  │    ├── echo-app/Application.yaml   ──► echo-app     │    │    │
│  │  │    └── podinfo/Application.yaml    ──► podinfo      │    │    │
│  │  └─────────────────────────────────────────────────────┘    │    │
│  │                                                             │    │
│  │  ┌────────────────┐  ┌────────────────┐  ┌─────────────┐    │    │
│  │  │  python-app    │  │   echo-app     │  │   podinfo   │    │    │
│  │  │  2 pods        │  │   2 pods       │  │   2 pods    │    │    │
│  │  │  (custom Flask)│  │  (public echo) │  │  (public)   │    │    │
│  │  └────────────────┘  └────────────────┘  └─────────────┘    │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
        ▲
        │  git push → ArgoCD auto-sync (~3 min)
        │
  GitHub repo  (gitops/apps/**/values.yaml)
```

---

## Tech Stack

| Concern | Tool | Reason |
|---|---|---|
| Local K8s cluster | k3d | Docker-based, lightweight, already installed |
| K8s cluster in TF | `pvotal-tech/k3d` provider | Native TF provider, proper state management |
| API gateway / ingress | Traefik | Built into k3d — no extra deployment |
| Routing config | Helm chart IngressRoute CRDs | Per-app IngressRoute + Middleware rendered by Helm |
| GitOps engine | ArgoCD | Declarative sync, auto-rollout on git push, App-of-Apps pattern |
| App deployment template | Shared Helm chart (`gitops/chart/`) | Portable, versioned, ArgoCD-native — replaces TF modules |
| App 1 (custom) | Python Flask + Dockerfile → Docker Hub | Demonstrates full build/push/deploy pipeline |
| App 2 (reuse demo) | `mendhak/http-https-echo` | Shows chart reusability with zero code change |
| App 3 (bonus) | `ghcr.io/stefanprodan/podinfo` | Same chart, two-file addition |
| Pod metadata | Kubernetes Downward API | Injects pod name + IP as env vars — no API calls |
| CI/CD | GitHub Actions + `act` (local) | `act` runs Actions locally in Docker |
| TF state | Local backend | No remote state needed for a local dev task |

---

## Prerequisites

- **Docker** — must be running
- **`terraform`** — `brew install terraform`
- **`k3d`** — `brew install k3d`
- **`kubectl`** — `brew install kubectl`
- **`helm`** — `brew install helm`
- **`argocd`** CLI — `brew install argocd` (optional, for inspecting sync status)
- **`.secrets`** file at the repo root (gitignored):

```
DOCKERHUB_USERNAME=<your-dockerhub-username>
DOCKERHUB_TOKEN=<your-dockerhub-token>
```

---

## Local Setup

```bash
# 1. Build and push the custom Python app image
make build

# 2. Initialise Terraform providers
make init

# 3. Create k3d cluster + deploy ArgoCD + bootstrap App-of-Apps
make apply

# 4. Wait for ArgoCD to sync all apps (~2-3 min)
kubectl -n argocd get applications
# python-app   Synced  Healthy
# echo-app     Synced  Healthy
# podinfo      Synced  Healthy

# 5. Verify all routes
make test
# or manually:
curl localhost/python-app   # {"pod_name":"...","pod_ip":"...","app":"python-app"}
curl localhost/echo-app     # JSON echo of the request
curl localhost/podinfo      # podinfo JSON response

# 6. Tear down
make destroy
```

---

## Makefile Reference

| Target | Description |
|---|---|
| `make cluster-create` | Create k3d cluster (ports 80/443, API 6445, 1 server + 1 agent) |
| `make cluster-delete` | Delete k3d cluster |
| `make build` | Build and push Python app image to Docker Hub |
| `make init` | `terraform -chdir=infra init` |
| `make plan` | `terraform -chdir=infra plan` |
| `make apply` | `cluster-create` → `terraform apply -auto-approve` |
| `make destroy` | `terraform destroy -auto-approve` → `cluster-delete` |
| `make test` | `curl -fsL` all three endpoints; exits non-zero on failure |
| `make all` | `build` → `init` → `apply` → `test` |

All targets source `.secrets` automatically — never run `docker build` or `terraform` directly if you need `DOCKERHUB_USERNAME` set.

---

## GitOps Flow

ArgoCD uses the **App-of-Apps** pattern:

1. Terraform creates a single "root" `Application` CRD that watches `gitops/apps/` in this repo.
2. ArgoCD discovers every `Application.yaml` under that path and creates a child Application for each.
3. Each child Application points to `gitops/chart/` as its Helm source and the sibling `values.yaml` as its values override.
4. Automated sync (`prune=true`, `selfHeal=true`) means any git push to a watched path triggers reconciliation within ~3 minutes.

**echo-app and podinfo** use the same shared chart as python-app. Their values files supply a different `image.repository` and (for podinfo) a different `service.port`. No chart code changes needed.

### Chart defaults and per-app overrides

`gitops/chart/values.yaml` defines the defaults for every app deployed by the shared chart
(e.g. `replicaCount: 2`, `image.pullPolicy: Always`). Each app's own
`gitops/apps/<name>/values.yaml` can override any of those defaults. Only the keys that
differ from the chart default need to be specified.

Example — scale python-app to 3 replicas while leaving echo-app at the default of 2:

```yaml
# gitops/apps/python-app/values.yaml
replicaCount: 3
```

### Rolling update example

```bash
# Edit gitops/apps/python-app/values.yaml: replicaCount: 3
git add gitops/apps/python-app/values.yaml
git commit -m "scale python-app to 3 replicas"
git push
# ArgoCD detects the commit and performs a rolling update — no downtime
```

### Adding a new app

Create two files and push:

```
gitops/apps/my-new-app/
  Application.yaml   ← ArgoCD Application CRD pointing to gitops/chart/
  values.yaml        ← image.repository, image.tag, path.prefix
```

No Terraform changes required.

---

## CI/CD Pipeline

```
git push to main
      │
      ▼
GitHub Actions
  ├── lint-and-validate  (always runs on push + PR)
  │     ├── paths-filter  →  sets app_changed / deploy_needed flags
  │     ├── terraform fmt -check
  │     ├── terraform init + validate
  │     └── helm lint gitops/chart/
  │
  └── deploy-and-test  (push to main only · skipped if only docs changed)
        ├── [if app/**]  docker build + push → Docker Hub
        ├── [if app/**]  yq: update image.tag in values.yaml + git commit + push
        ├── k3d cluster create  (k3d-config.yaml)
        ├── terraform apply
        │     ├── ArgoCD helm release  (argocd namespace)
        │     └── App-of-Apps root Application CRD
        ├── kubectl wait --for=condition=Synced application/python-app
        ├── make test  (curl /python-app /echo-app /podinfo)
        └── make destroy  (always · terraform destroy + cluster delete)
```

**Path filtering**: `dorny/paths-filter` gates the `deploy-and-test` job on changes to
`app/**`, `infra/**`, `gitops/**`, or `k3d-config.yaml`. A docs-only commit runs lint only.
Docker build and image tag steps run only when `app/**` changes; infrastructure-only changes
skip straight to cluster creation.

**Infra change validation**: CI provisions a fresh ephemeral cluster, tests it end-to-end,
then destroys it. This intentionally accepts brief test-environment downtime. In production
the equivalent would be a DNS or load-balancer cutover between two clusters
(blue/green) — not applicable to a single-host local k3d setup.

**Local testing**:
```bash
act push --secret-file .secrets
```

**Required GitHub secrets**: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

---

## Design Decisions

**Shared Helm chart over Terraform modules**  
All three apps are deployed by the same `gitops/chart/`. Adding an app is two files and a
git push. Using a Terraform module instead would require a `terraform apply` for every new
app — the wrong tool for a GitOps workflow.

**Traefik built into k3d**  
k3d ships Traefik as the default ingress controller. Deploying a second controller (nginx,
etc.) would be redundant. Traefik's `IngressRoute` and `Middleware` CRDs handle strip-prefix
routing cleanly via Helm-templated manifests in the shared chart.

**Downward API for pod metadata**  
Pod name and IP are injected as environment variables at runtime using the Kubernetes
Downward API. The app reads `POD_NAME` and `POD_IP` directly from env — no Kubernetes API
client, no RBAC config, no extra dependencies.

**ArgoCD App-of-Apps**  
The only Terraform-managed ArgoCD resource is the root `Application` CRD. Child applications
are discovered automatically from `gitops/apps/`. This means Terraform owns infrastructure
(cluster, ArgoCD install, root bootstrap) while ArgoCD owns workloads — clean separation of
concerns.

---

## AI Usage

[Claude Code](https://claude.com/claude-code) (`claude-sonnet-4-6`) assisted throughout
this project:

- Architecture decisions were made collaboratively — every tech choice was confirmed by the
  human before any code was written
- The shift from direct Helm-from-Terraform to an ArgoCD GitOps pattern was a human
  decision made after evaluating options with Claude
- Claude generated: shared Helm chart, Terraform files, Python app and Dockerfile,
  CI/CD workflow, and Makefile
- Human reviewed all generated output before committing
- Prompts and design rationale are captured in `CLAUDE.md`
