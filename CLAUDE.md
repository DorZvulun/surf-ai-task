# CLAUDE.md — Terraform K8s Candidate Task

## Project Overview

Senior DevOps candidate take-home assignment. Provision a local Kubernetes cluster using
Terraform, deploy N web applications via a GitOps pipeline backed by ArgoCD, expose them
through an API gateway with distinct routes, and build a CI/CD pipeline. Submit via public
GitHub repo.

The goal is to demonstrate: IaC proficiency, GitOps delivery, code reusability (DRY),
Kubernetes networking knowledge, and CI/CD automation.

---

## Technology Decisions

| Concern | Tool | Reason |
|---|---|---|
| Local K8s cluster | k3d | Already installed; Docker-based; lightweight |
| K8s cluster in TF | `pvotal-tech/k3d` provider | Native TF provider, proper state management |
| API gateway / ingress | Traefik | Built into k3d by default — no extra deployment |
| Routing config | Helm chart templates (IngressRoute CRDs) | Per-app IngressRoute + Middleware rendered by Helm |
| GitOps engine | ArgoCD | Declarative sync, auto-rollout on git push, App-of-Apps pattern |
| App deployment template | Helm chart (`gitops/chart/`) | Replaces TF module; portable, versioned, ArgoCD-native |
| App 1 (custom) | Python + Dockerfile → Docker Hub | Demonstrates full build/push/deploy pipeline |
| App 2 (reuse demo) | `mendhak/http-https-echo` public image | Shows chart reusability with zero code change |
| App 3 (bonus) | podinfo via ArgoCD + shared Helm chart | Demonstrates chart reusability — same chart, 2-file addition |
| Pod metadata | Kubernetes Downward API | Injects pod name + IP as env vars — no API calls |
| CI/CD | GitHub Actions + `act` (local) | `act` runs Actions locally in Docker |
| TF state | local backend | No remote state needed for a local dev task |

**Do not deviate from these choices.** Do not use kind, minikube, nginx-ingress, local-exec
for cluster management, or any cloud resources.

---

## Repository Structure

```
/
├── CLAUDE.md
├── README.md
├── Makefile
├── k3d-config.yaml              # k3d cluster config (ports, nodes)
│
├── app/                         # Custom Python web app
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
│
├── gitops/                      # ArgoCD-watched content
│   ├── chart/                   # Shared Helm chart (replaces modules/web-app/)
│   │   ├── Chart.yaml
│   │   ├── values.yaml          # chart defaults
│   │   └── templates/
│   │       ├── deployment.yaml  # Downward API env vars
│   │       ├── service.yaml
│   │       └── ingressroute.yaml  # Traefik IngressRoute + Middleware CRDs
│   └── apps/                    # App-of-Apps root — each subdir is one app
│       ├── ironman-web-app/
│       │   ├── Application.yaml # ArgoCD Application CRD
│       │   └── values.yaml      # image.tag, replicaCount, path.prefix
│       └── echo-app/
│           ├── Application.yaml
│           └── values.yaml
│
├── infra/                       # All Terraform code
│   ├── main.tf                  # terraform block, required_providers, backend
│   ├── cluster.tf               # k3d data source (see nodes.md for provider bug)
│   ├── argocd.tf                # ArgoCD namespace + helm_release
│   ├── argocd-apps.tf           # Root App-of-Apps Application CRD
│   ├── podinfo.tf               # helm_release for podinfo (bonus)
│   ├── variables.tf             # var.docker_username, var.repo_url
│   ├── outputs.tf
│   └── terraform.tfvars         # repo_url, docker_username
│
└── .github/
    └── workflows/
        └── ci.yml
```

---

## Terraform Conventions

- **Provider versions**: pin all providers with `~>` constraints in `infra/main.tf`
- **Naming**: all resource names use the app name as prefix — no hardcoded strings
- **Namespace**: default to `"default"` but accept as Helm values override
- **No hardcoded values**: image names, replicas, paths — all come from Helm values files
- **State**: local backend, state file at `infra/terraform.tfstate`
- **Format**: all `.tf` files must pass `terraform fmt -check`

### Required providers (infra/main.tf)

```hcl
terraform {
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = "~> 0.0.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}
```

Configure the kubernetes and helm providers using the kubeconfig from `~/.kube/config`
with context `k3d-surf-cluster` (written by k3d when the cluster is created).

---

## App Definitions

Apps live in `gitops/apps/<name>/`. Each directory contains two files:

- **`Application.yaml`** — ArgoCD Application CRD that points to `gitops/chart/` as
  the Helm chart source and `../apps/<name>/values.yaml` as the values override.
- **`values.yaml`** — Helm values specific to this app: `image.repository`, `image.tag`,
  `replicaCount`, `path.prefix`.

**Adding a new app = add these two files and push. No Terraform changes required.**

`DOCKERHUB_USERNAME` is never hardcoded in any committed file. It is read from `.secrets`
at runtime. The ironman-web-app image is built as `$DOCKERHUB_USERNAME/ironman-web-app`.

`var.docker_username` is populated via the `TF_VAR_docker_username` env var, which the
Makefile exports automatically by sourcing `.secrets`.

CI secrets required: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

---

## Helm Chart Interface (gitops/chart/)

The shared Helm chart is the single deployable unit for all web apps. It replaces the
`modules/web-app/` Terraform module from the original design.

### Default values (values.yaml)

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `2` | Pod replica count |
| `image.repository` | `""` | Docker image repository |
| `image.tag` | `"latest"` | Image tag — updated by CI to git SHA |
| `image.pullPolicy` | `Always` | Always pull to pick up new pushes |
| `path.prefix` | `"/"` | Traefik route path prefix |
| `namespace` | `"default"` | Kubernetes namespace |

### What the chart creates

1. `Deployment` — with Downward API env vars for pod name and IP
2. `Service` — ClusterIP pointing to the deployment
3. `IngressRoute` — Traefik CRD for path-based routing (`traefik.io/v1alpha1`)
4. `Middleware` — Traefik strip-prefix (removes path prefix before forwarding)

Resource names follow the pattern `{{ .Release.Name }}-<type>` (e.g., `ironman-web-app-svc`).

---

## Downward API Pattern

Every pod created by the chart must expose pod name and IP as env vars. Use this exact
pattern in `gitops/chart/templates/deployment.yaml`:

```yaml
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
```

---

## Python App (app/)

- **Framework**: Flask or FastAPI — whichever is simpler
- **Response**: JSON only — `{"pod_name": "...", "pod_ip": "...", "app": "ironman-web-app"}`
- **Port**: 8080
- **Reads from env**: `POD_NAME`, `POD_IP` — injected by Downward API at runtime
- **Dockerfile**: multi-stage is NOT required; keep it simple and small
- **Image name**: `ironman-web-app` — prefixed with `$DOCKERHUB_USERNAME` at build time
- **Tags**: use `latest` for local dev; use git SHA (`$GITHUB_SHA`) in CI

---

## Traefik Routing

k3d ships with Traefik on `localhost:80` (HTTP) and `localhost:443` (HTTPS). Do not deploy
a second ingress controller.

Routing pattern: each app gets a distinct path prefix with strip-prefix middleware so the
upstream app sees `/` not `/ironman-web-app/`.

```
localhost/ironman-web-app  → ironman-web-app pods  (strip /ironman-web-app)
localhost/echo-app    → echo-app pods    (strip /echo-app)
localhost/podinfo     → podinfo pods     (strip /podinfo)
```

`IngressRoute` and `Middleware` CRDs for web apps are defined in
`gitops/chart/templates/ingressroute.yaml` and rendered by ArgoCD via Helm.
For podinfo (one-off), they are defined as `kubernetes_manifest` in `infra/podinfo.tf`.

The CRD group is `traefik.io/v1alpha1`.

---

## ArgoCD (infra/argocd.tf + infra/argocd-apps.tf)

### Deployment

ArgoCD is deployed via `helm_release` into the `argocd` namespace. Terraform creates
the namespace and the Helm release.

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
}
```

### App-of-Apps root Application

A single Terraform-managed ArgoCD `Application` (the "root app") watches `gitops/apps/`.
ArgoCD finds all `Application.yaml` files in that directory and creates child Applications.

```hcl
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "surf-apps"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = "HEAD"
        path           = "gitops/apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  }
}
```

### Sync policy

All ArgoCD Applications use `syncPolicy.automated` with `prune = true` and
`selfHeal = true`. Any push to the monitored paths triggers immediate reconciliation.

---

## Podinfo (Bonus — gitops/apps/podinfo/)

Deployed via the shared Helm chart through ArgoCD — same pattern as ironman-web-app and echo-app.
Two files added, zero Terraform changes. This is the point: the bonus task demonstrates
chart reusability.

- `gitops/apps/podinfo/Application.yaml` — ArgoCD Application pointing to `gitops/chart/`
- `gitops/apps/podinfo/values.yaml` — sets `image.repository: ghcr.io/stefanprodan/podinfo`,
  `service.port: 9898`, `path.prefix: /podinfo`

The shared chart's `service.port` value (default `8080`) allows any app with a different
container port to override it via values.

---

## Docker Build & Push

### Local build

Values come from `.secrets` (sourced by the Makefile — never run docker build manually):

```bash
make build  # sources .secrets, then: docker build + push $DOCKERHUB_USERNAME/ironman-web-app:latest
```

### CI build

In GitHub Actions, build on every push to `main`, tag with `$GITHUB_SHA` and `latest`.
Credentials come from secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

After pushing, CI updates `gitops/apps/ironman-web-app/values.yaml` with the new image tag
and commits the change. ArgoCD detects the commit and triggers a rolling update.

---

## Makefile Targets

All Makefile commands must work from the repo root. Terraform is run with `-chdir=infra`.

The Makefile must source `.secrets` and export all vars so that:
- `$(DOCKERHUB_USERNAME)` is available for `docker build/push`
- `TF_VAR_docker_username` is set for Terraform automatically

```makefile
include .secrets
export
```

| Target | Description |
|---|---|
| `make cluster-create` | Create k3d cluster via CLI (ports 80/443, API 6445, 1 server + 1 agent) |
| `make cluster-delete` | Delete k3d cluster (`k3d cluster delete surf-cluster`) |
| `make build` | Build and push Python app image to Docker Hub |
| `make init` | `terraform -chdir=infra init` |
| `make plan` | `terraform -chdir=infra plan` |
| `make apply` | `cluster-create` → `terraform -chdir=infra apply -auto-approve` |
| `make destroy` | `terraform -chdir=infra destroy -auto-approve` → `cluster-delete` |
| `make test` | curl all app endpoints and assert HTTP 200 |
| `make all` | build → init → apply → test |

The `test` target must check each route and exit non-zero on failure. Use curl with `-f`
flag and print what was returned.

---

## CI/CD — GitHub Actions

File: `.github/workflows/ci.yml`

### Trigger
- Push to `main`
- Pull requests to `main`

### Jobs

**lint-and-validate** (runs first):
1. Checkout
2. Setup Terraform
3. `terraform -chdir=infra fmt -check`
4. `terraform -chdir=infra init`
5. `terraform -chdir=infra validate`
6. Setup Helm
7. `helm lint gitops/chart/`

**deploy-and-test** (runs after lint-and-validate, only on push to main):
1. Checkout
2. Setup Docker Buildx
3. Login to Docker Hub (secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`)
4. Build and push image (tag: `$GITHUB_SHA` and `latest`)
5. Update `gitops/apps/ironman-web-app/values.yaml` image tag to `$GITHUB_SHA` via `yq`
6. Commit `[ci] update ironman-web-app image to $GITHUB_SHA` and push
7. Install k3d on the runner
8. Setup Terraform
9. `make init`
10. `make apply` (creates cluster + terraform apply → ArgoCD deploys apps)
11. Wait for ArgoCD sync: `kubectl -n argocd wait --for=condition=Synced application/ironman-web-app --timeout=120s`
12. `make test`
13. `make destroy` (always runs, even on failure — use `if: always()`)

### Local testing with act

Install: `brew install act`

Run the full workflow locally:
```bash
act push --secret-file .secrets
```

`.secrets` file (gitignored):
```
DOCKERHUB_USERNAME=<your-dockerhub-username>
DOCKERHUB_TOKEN=<your-dockerhub-token>
```

---

## How to Run Locally

### Prerequisites

- Docker running
- `terraform` installed (`brew install terraform`)
- `k3d` installed (`brew install k3d`)
- `kubectl` installed
- `helm` installed
- `argocd` CLI installed (`brew install argocd`) — optional, for inspecting sync status
- `.secrets` file populated with `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`

### Steps

```bash
# 1. Build and push the custom Python app
make build

# 2. Provision cluster + deploy ArgoCD + bootstrap App-of-Apps
make init
make apply

# 3. Wait for ArgoCD to sync apps
kubectl -n argocd get applications   # ironman-web-app, echo-app: Synced/Healthy

# 4. Verify
make test
# or manually:
curl localhost/ironman-web-app
curl localhost/echo-app
curl localhost/podinfo

# 5. GitOps update example — scale ironman-web-app
# Edit gitops/apps/ironman-web-app/values.yaml: replicaCount: 2 → 3
git add . && git commit -m "scale ironman-web-app to 3" && git push
# ArgoCD syncs within ~3 minutes

# 6. Tear down
make destroy
```

---

## What NOT to Do

- Do not use `kind` — not installed, not the chosen tool
- Do not use `local-exec` to manage the k3d cluster — use the `pvotal-tech/k3d` provider (or CLI via Makefile as documented in nodes.md)
- Do not deploy nginx-ingress — Traefik is already in k3d
- Do not hardcode `DOCKER_USERNAME` or image names anywhere in `.tf` files or `values.yaml`
- Do not manage app Deployments, Services, or IngressRoutes from Terraform directly — ArgoCD owns that
- Do not add new apps by editing Terraform files — add `gitops/apps/<name>/` files and push
- Do not create a separate TF state or backend per module
- Do not add `helm_release` for things that already have a native TF/K8s resource
- Do not add CI/CD steps that aren't in the workflow defined above
- Do not skip `terraform fmt` — all `.tf` files must be formatted
- Do not use `kubernetes_manifest` for resources that have a dedicated TF resource type;
  ArgoCD `Application` CRDs have no dedicated type, so `kubernetes_manifest` is correct there

---

## AI Usage Notes (for README.md)

Document honestly in the README:
- Claude Code (claude-sonnet-4-6) was used to assist with this task
- Architecture decisions were made collaboratively (human-in-the-loop on every choice)
- All tech stack decisions: human confirmed before any code was written (including the shift to ArgoCD GitOps)
- Claude Code generated the Helm chart, TF infrastructure, Python app, Dockerfile, and CI workflow
- Human reviewed all output before committing
- Prompts and design discussion captured in this CLAUDE.md
