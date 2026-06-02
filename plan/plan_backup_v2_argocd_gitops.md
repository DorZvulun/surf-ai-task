# Plan: Shift to ArgoCD GitOps Architecture

## Context

The original CLAUDE.md design had Terraform directly managing Kubernetes Deployments,
Services, and Traefik IngressRoutes via a `modules/web-app/` Terraform module and
`infra/apps.tf`. The user wants a proper GitOps flow where ArgoCD is the deployment
engine: changes to a Helm values file (image tag, replicas) in the Git repo trigger
rolling updates or scale events automatically, without running `terraform apply`.

Tasks 1–3 are done (providers, cluster). Tasks 4–14 need to be revised.
CLAUDE.md itself will be updated to reflect the new design.

---

## What Changes vs. Original Spec

| Area | Old | New |
|---|---|---|
| App lifecycle manager | Terraform (`kubernetes_deployment` etc.) | ArgoCD |
| Reusable app abstraction | `modules/web-app/` Terraform module | `gitops/chart/` Helm chart |
| App definitions | `infra/terraform.tfvars` apps map | `gitops/apps/<name>/Application.yaml` + `values.yaml` |
| Adding a new app | Add one block to tfvars | Add two files to `gitops/apps/` — zero Terraform changes |
| Image update trigger | `terraform apply` | CI commits new SHA tag → git push → ArgoCD auto-syncs |
| `infra/apps.tf` | Creates k8s resources directly | **Deleted** |
| `infra/argocd-apps.tf` | n/a | ONE root Application (App-of-Apps bootstrap) |
| `modules/web-app/` | Terraform module | **Deleted** — replaced by Helm chart |
| podinfo | `helm_release` in Terraform | Stays as direct `helm_release` (one-off, no GitOps overhead) |

---

## Revised Repository Structure

```
/
├── app/                              # Python app — UNCHANGED
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
│
├── gitops/                           # NEW: everything ArgoCD watches
│   ├── chart/                        # Shared Helm chart (replaces modules/web-app/)
│   │   ├── Chart.yaml
│   │   ├── values.yaml               # chart defaults
│   │   └── templates/
│   │       ├── deployment.yaml       # includes Downward API env vars
│   │       ├── service.yaml
│   │       └── ingressroute.yaml     # Traefik IngressRoute + Middleware CRDs
│   └── apps/                         # ArgoCD root app watches this directory
│       ├── python-app/
│       │   ├── Application.yaml      # ArgoCD Application CRD
│       │   └── values.yaml           # image.tag, replicaCount, path.prefix
│       └── echo-app/
│           ├── Application.yaml
│           └── values.yaml
│
├── infra/
│   ├── main.tf                       # providers + backend — UNCHANGED
│   ├── cluster.tf                    # k3d data source — UNCHANGED
│   ├── argocd.tf                     # NEW: helm_release "argocd" + argocd namespace
│   ├── argocd-apps.tf                # NEW: ONE root App-of-Apps Application
│   ├── podinfo.tf                    # helm_release for podinfo — same concept
│   ├── variables.tf                  # var.docker_username + var.repo_url only
│   ├── outputs.tf                    # argocd admin password, ArgoCD URL
│   └── terraform.tfvars              # repo_url, docker_username (no apps map)
│
├── modules/                          # DELETED
│
└── .github/workflows/ci.yml          # REVISED — adds image tag update + git commit step
```

---

## Architecture: App-of-Apps Pattern

Terraform creates **one** ArgoCD Application (the "root app") that watches `gitops/apps/`.
ArgoCD finds all `Application.yaml` files in that directory and creates child Applications.
Each child Application points to `gitops/chart/` as the chart source, with its own
`values.yaml` for overrides.

```
Terraform
  └── helm_release "argocd"
  └── kubernetes_manifest "argocd_root_app"   ← watches gitops/apps/
        └── ArgoCD syncs gitops/apps/
              ├── python-app/Application.yaml  ← child app
              │     source: gitops/chart + ../python-app/values.yaml
              └── echo-app/Application.yaml    ← child app
                    source: gitops/chart + ../echo-app/values.yaml
```

**Adding a new app (zero Terraform changes):**
1. Add `gitops/apps/new-app/Application.yaml` (copy/adapt from existing)
2. Add `gitops/apps/new-app/values.yaml` (image, replicas, path)
3. `git push` → ArgoCD root app picks it up → child app created → pods running

---

## Design Details

### `gitops/chart/` — Helm chart (replaces `modules/web-app/`)

`values.yaml` defaults:
```yaml
replicaCount: 2
image:
  repository: ""
  tag: "latest"
  pullPolicy: Always
path:
  prefix: "/"
namespace: default
```

`templates/deployment.yaml` — Downward API env vars:
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

`templates/ingressroute.yaml` — Traefik CRDs:
- `IngressRoute` (traefik.io/v1alpha1) matching `PathPrefix('{{ .Values.path.prefix }}')`
- `Middleware` with `stripPrefix.prefixes: ["{{ .Values.path.prefix }}"]`

### `gitops/apps/python-app/Application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: python-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/DorZvulun/surf-ai-task
    targetRevision: HEAD
    path: gitops/chart
    helm:
      valueFiles:
        - ../apps/python-app/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### `infra/argocd.tf` — ArgoCD deployment

```hcl
resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  depends_on = [kubernetes_namespace.argocd]
}
```

### `infra/argocd-apps.tf` — Root App-of-Apps

```hcl
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "apps"
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
  depends_on = [helm_release.argocd]
}
```

### CI image update flow

```yaml
# .github/workflows/ci.yml — after docker push
- name: Update image tag in gitops
  run: |
    yq e '.image.tag = "${{ github.sha }}"' -i \
      gitops/apps/python-app/values.yaml
    git config user.email "ci@github.com"
    git config user.name "GitHub Actions"
    git commit -am "[ci] update python-app image to ${{ github.sha }}"
    git push
```
ArgoCD detects the commit (default 3-minute poll or webhook) and triggers rolling update.

### Traefik routing — unchanged
```
localhost/python-app  → python-app pods  (strip prefix)
localhost/echo-app    → echo-app pods    (strip prefix)
localhost/podinfo     → podinfo pods     (direct helm_release)
```

---

## Revised Task List (Tasks 4–14)

**Task 4** (unchanged): `app/main.py` + `requirements.txt`

**Task 5** (unchanged): `app/Dockerfile`

**Task 6** (unchanged): Docker build + push

**Task 7** (CHANGED — was TF module): Write `gitops/chart/` Helm chart
- `Chart.yaml`, `values.yaml`
- `templates/deployment.yaml` (Downward API)
- `templates/service.yaml`
- `templates/ingressroute.yaml` (Traefik CRDs)
- Output: `helm template` renders valid YAML

**Task 8** (CHANGED): Deploy ArgoCD + bootstrap App-of-Apps + per-app files
- `infra/argocd.tf`: namespace + ArgoCD helm_release
- `infra/argocd-apps.tf`: root Application pointing at `gitops/apps/`
- `infra/variables.tf`: `var.repo_url`, `var.docker_username`
- `infra/terraform.tfvars`: concrete values
- `gitops/apps/python-app/Application.yaml` + `values.yaml`
- `gitops/apps/echo-app/Application.yaml` + `values.yaml`
- Output: `terraform validate` passes

**Task 9** (CHANGED): `terraform apply` → ArgoCD syncs → verify endpoints
- ArgoCD auto-syncs child apps → pods running
- `curl localhost/python-app` and `curl localhost/echo-app` return 200 JSON

**Task 10** (unchanged concept): `infra/podinfo.tf` — direct `helm_release` + IngressRoute

**Task 11** (REVISED): Makefile
- `cluster-create` / `cluster-delete` targets
- `make apply` = cluster-create → terraform apply
- `make destroy` = terraform destroy → cluster-delete
- `make test` = curl all endpoints

**Task 12** (REVISED): CI lint job — terraform fmt/validate + `helm lint gitops/chart/`

**Task 13** (REVISED): CI deploy job
- Build + push image
- Update `gitops/apps/python-app/values.yaml` image tag, commit + push
- k3d create → terraform apply → wait for ArgoCD sync → `make test`

**Task 14** (REVISED): README — document GitOps flow, ArgoCD UI access, how to scale/upgrade

---

## Files to Delete
- `modules/web-app/` (entire directory — replaced by `gitops/chart/`)
- `infra/apps.tf` (would have been created, now not needed)

---

## Verification

```bash
# 1. Cluster + ArgoCD up
make cluster-create && make init && make apply
kubectl -n argocd get pods         # all Running

# 2. ArgoCD synced apps
kubectl get applications -n argocd  # python-app, echo-app: Synced/Healthy

# 3. Endpoints
make test
# curl localhost/python-app → {"pod_name":"...","pod_ip":"...","app":"python-app"}
# curl localhost/echo-app   → echo response
# curl localhost/podinfo    → podinfo UI

# 4. GitOps scale test
# Edit gitops/apps/python-app/values.yaml: replicaCount 2 → 3, git push
kubectl get pods | grep python-app  # 3 pods after ArgoCD sync (~3 min)

# 5. Image update test (simulated)
# Edit image.tag in values.yaml, git push → ArgoCD rolling update

# 6. Teardown
make destroy
```
