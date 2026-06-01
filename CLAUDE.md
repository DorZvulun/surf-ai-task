# CLAUDE.md — Terraform K8s Candidate Task

## Project Overview

Senior DevOps candidate take-home assignment. Provision a local Kubernetes cluster using
Terraform, deploy N web applications via a reusable module, expose them through an API
gateway with distinct routes, and build a CI/CD pipeline. Submit via public GitHub repo.

The goal is to demonstrate: IaC proficiency, code reusability (DRY), Kubernetes networking
knowledge, and CI/CD automation.

---

## Technology Decisions

| Concern | Tool | Reason |
|---|---|---|
| Local K8s cluster | k3d | Already installed; Docker-based; lightweight |
| K8s cluster in TF | `pvotal-tech/k3d` provider | Native TF provider, proper state management |
| API gateway / ingress | Traefik | Built into k3d by default — no extra deployment |
| Routing config | `kubernetes_manifest` (IngressRoute CRDs) | Traefik uses CRDs, not standard Ingress |
| App 1 (custom) | Python + Dockerfile → Docker Hub | Demonstrates full build/push/deploy pipeline |
| App 2 (reuse demo) | `mendhak/http-https-echo` public image | Shows module reusability with zero code change |
| App 3 (bonus) | podinfo via `helm_release` | Demonstrates Helm provider integration |
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
├── infra/                       # All Terraform code
│   ├── main.tf                  # terraform block, required_providers, backend
│   ├── cluster.tf               # k3d cluster resource
│   ├── traefik.tf               # Traefik middleware + strip-prefix config
│   ├── apps.tf                  # for_each over var.apps → module instantiation
│   ├── podinfo.tf               # helm_release for podinfo (bonus)
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars         # app definitions live here
│
├── modules/
│   └── web-app/                 # Reusable module: Deployment + Service + IngressRoute
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── .github/
    └── workflows/
        └── ci.yml
```

---

## Terraform Conventions

- **Provider versions**: pin all providers with `~>` constraints in `infra/main.tf`
- **Naming**: all resource names use `var.app_name` as prefix — no hardcoded strings
- **Namespace**: default to `"default"` but accept as module variable
- **No hardcoded values**: image names, replicas, paths — all come from variables
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

Configure the kubernetes and helm providers using the kubeconfig output from the k3d cluster
resource so there are no chicken-and-egg dependency issues.

---

## App Definitions

Apps are defined as a map in `infra/terraform.tfvars`. Adding a new app = adding one block
here and nothing else.

```hcl
apps = {
  python-app = {
    image       = "DOCKER_USERNAME/APP_IMAGE_NAME:latest"
    replicas    = 2
    path_prefix = "/python-app"
  }
  echo-app = {
    image       = "mendhak/http-https-echo:latest"
    replicas    = 2
    path_prefix = "/echo-app"
  }
}
```

`DOCKER_USERNAME` and `APP_IMAGE_NAME` are placeholders. Set them via:
- Local: `export TF_VAR_docker_username=yourusername` before running terraform
- CI: set as GitHub Actions secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_IMAGE_NAME`

---

## Web App Module Interface (modules/web-app)

### Variables

| Variable | Type | Required | Description |
|---|---|---|---|
| `app_name` | string | yes | Used for all resource names |
| `image` | string | yes | Full image reference |
| `replicas` | number | no (default: 2) | Pod replica count |
| `path_prefix` | string | yes | Traefik route path, e.g. `/python-app` |
| `namespace` | string | no (default: "default") | K8s namespace |
| `env_vars` | map(string) | no | Extra env vars to inject |

### What the module creates

1. `kubernetes_deployment` — with Downward API env vars for pod name and IP
2. `kubernetes_service` — ClusterIP pointing to the deployment
3. `kubernetes_manifest` — Traefik `IngressRoute` CRD for path-based routing
4. `kubernetes_manifest` — Traefik `Middleware` for strip-prefix (removes path prefix before forwarding)

### Outputs

| Output | Description |
|---|---|
| `service_name` | Name of the created Service |
| `deployment_name` | Name of the created Deployment |
| `route_path` | The path_prefix value (for use in README/test commands) |

---

## Downward API Pattern

Every pod in the web-app module must expose pod name and IP as env vars using the Downward
API. Use this exact pattern in the deployment container spec:

```hcl
env {
  name = "POD_NAME"
  value_from {
    field_ref { field_path = "metadata.name" }
  }
}
env {
  name = "POD_IP"
  value_from {
    field_ref { field_path = "status.podIP" }
  }
}
```

---

## Python App (app/)

- **Framework**: Flask or FastAPI — whichever is simpler
- **Response**: JSON only — `{"pod_name": "...", "pod_ip": "...", "app": "python-app"}`
- **Port**: 8080
- **Reads from env**: `POD_NAME`, `POD_IP` — injected by Downward API at runtime
- **Dockerfile**: multi-stage is NOT required; keep it simple and small
- **Image name**: placeholder `APP_IMAGE_NAME` — set by the developer, do not hardcode
- **Tags**: use `latest` for local dev; use git SHA (`$GITHUB_SHA`) in CI

---

## Traefik Routing

k3d ships with Traefik on `localhost:80` (HTTP) and `localhost:443` (HTTPS). Do not deploy
a second ingress controller.

Routing pattern: each app gets a distinct path prefix with strip-prefix middleware so the
upstream app sees `/` not `/python-app/`.

```
localhost/python-app  → python-app pods  (strip /python-app)
localhost/echo-app    → echo-app pods    (strip /echo-app)
localhost/podinfo     → podinfo pods     (strip /podinfo)
```

Use `kubernetes_manifest` for all Traefik CRD resources (`IngressRoute`, `Middleware`).
The CRD group is `traefik.io/v1alpha1`.

---

## Podinfo (Bonus — infra/podinfo.tf)

Deploy using the official Helm chart. Expose via a Traefik IngressRoute at `/podinfo`.

```hcl
resource "helm_release" "podinfo" {
  name       = "podinfo"
  repository = "https://stefanprodan.github.io/podinfo"
  chart      = "podinfo"
  namespace  = "default"

  set {
    name  = "ui.message"
    value = "Hello from podinfo"
  }
}
```

Add the IngressRoute for podinfo in `infra/podinfo.tf` (not inside a module — it's a
one-off with a different structure).

---

## Docker Build & Push

### Local build

```bash
docker build -t ${DOCKER_USERNAME}/${APP_IMAGE_NAME}:latest ./app
docker push ${DOCKER_USERNAME}/${APP_IMAGE_NAME}:latest
```

### CI build

In GitHub Actions, build on every push to `main`, tag with `$GITHUB_SHA` and `latest`.
Credentials come from secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

---

## Makefile Targets

All Makefile commands must work from the repo root. Terraform is run with `-chdir=infra`.

| Target | Description |
|---|---|
| `make build` | Build and push Python app image to Docker Hub |
| `make init` | `terraform -chdir=infra init` |
| `make plan` | `terraform -chdir=infra plan` |
| `make apply` | `terraform -chdir=infra apply -auto-approve` |
| `make destroy` | `terraform -chdir=infra destroy -auto-approve` |
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

**deploy-and-test** (runs after lint-and-validate, only on push to main):
1. Checkout
2. Setup Docker Buildx
3. Login to Docker Hub (secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`)
4. Build and push image (tag: `$GITHUB_SHA` and `latest`)
5. Install k3d on the runner
6. Setup Terraform
7. `make init`
8. `make apply` (with `TF_VAR_docker_username` set from secret)
9. `make test`
10. `make destroy` (always runs, even on failure — use `if: always()`)

### Local testing with act

Install: `brew install act`

Run the full workflow locally:
```bash
act push --secret-file .secrets
```

`.secrets` file (gitignored):
```
DOCKERHUB_USERNAME=yourusername
DOCKERHUB_TOKEN=yourtoken
DOCKERHUB_IMAGE_NAME=yourimage
```

---

## How to Run Locally

### Prerequisites

- Docker running
- `terraform` installed (`brew install terraform`)
- `k3d` installed (`brew install k3d`)
- `kubectl` installed
- `helm` installed
- Docker Hub account with `DOCKER_USERNAME` and `APP_IMAGE_NAME` decided

### Steps

```bash
# 1. Set your Docker vars
export DOCKER_USERNAME=yourusername
export APP_IMAGE_NAME=your-image-name
export TF_VAR_docker_username=$DOCKER_USERNAME
export TF_VAR_app_image_name=$APP_IMAGE_NAME

# 2. Build and push the custom Python app
make build

# 3. Provision cluster + deploy everything
make init
make apply

# 4. Verify
make test
# or manually:
curl localhost/python-app
curl localhost/echo-app
curl localhost/podinfo

# 5. Tear down
make destroy
```

---

## What NOT to Do

- Do not use `kind` — not installed, not the chosen tool
- Do not use `local-exec` to manage the k3d cluster — use the `pvotal-tech/k3d` provider
- Do not deploy nginx-ingress — Traefik is already in k3d
- Do not hardcode `DOCKER_USERNAME` or image names anywhere in `.tf` files
- Do not define apps anywhere except `infra/terraform.tfvars`
- Do not create a separate TF state or backend per module
- Do not add `helm_release` for things that already have a native TF/K8s resource
- Do not add CI/CD steps that aren't in the workflow defined above
- Do not skip `terraform fmt` — all files must be formatted
- Do not use `kubernetes_manifest` for resources that have a dedicated TF resource type
  (e.g., use `kubernetes_deployment`, not `kubernetes_manifest`, for Deployments)

---

## AI Usage Notes (for README.md)

Document honestly in the README:
- Claude Code (claude-sonnet-4-6) was used to assist with this task
- Architecture decisions were made collaboratively (human-in-the-loop on every choice)
- All tech stack decisions: human confirmed before any code was written
- Claude Code generated TF modules, Python app, Dockerfile, and CI workflow
- Human reviewed all output before committing
- Prompts and design discussion captured in this CLAUDE.md
