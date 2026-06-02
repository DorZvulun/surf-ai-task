# Plan: Task 8 — ArgoCD Infrastructure + App-of-Apps Bootstrap

## Context

Task 7 created the shared Helm chart. Task 8 wires up the GitOps engine: Terraform deploys
ArgoCD, bootstraps a single "root" Application that watches `gitops/apps/`, and ArgoCD's
App-of-Apps pattern creates child Applications for each app in that directory.

Success criteria: `terraform validate` passes; all YAML files are valid; ArgoCD Application
manifests are well-formed.

Existing files: `infra/main.tf` (providers), `infra/cluster.tf` (k3d data source).

---

## Files to Create

### `infra/variables.tf`
```hcl
variable "repo_url" {
  description = "GitHub repository URL watched by ArgoCD"
  type        = string
}

variable "docker_username" {
  description = "Docker Hub username (set via TF_VAR_docker_username — never hardcoded)"
  type        = string
  default     = ""
}
```

### `infra/terraform.tfvars`
Only `repo_url` is committed. `docker_username` comes from `TF_VAR_docker_username` env
var (Makefile sources `.secrets`). Read `git remote get-url origin` at implementation time
to get the actual URL.

```hcl
repo_url = "https://github.com/<user>/<repo>"
```

### `infra/argocd.tf`
Two resources:
1. `kubernetes_namespace "argocd"` — creates the `argocd` namespace
2. `helm_release "argocd"` — installs ArgoCD from `https://argoproj.github.io/argo-helm`,
   chart `argo-cd`, namespace `argocd`, `depends_on = [kubernetes_namespace.argocd]`

### `infra/argocd-apps.tf`
One `kubernetes_manifest "argocd_root_app"` — the App-of-Apps root Application.
- `apiVersion: argoproj.io/v1alpha1`, `kind: Application`
- `metadata.name = "apps"`, `metadata.namespace = "argocd"`
- `spec.source.repoURL = var.repo_url`
- `spec.source.targetRevision = "HEAD"`
- `spec.source.path = "gitops/apps"`
- `spec.destination.server = "https://kubernetes.default.svc"`
- `spec.destination.namespace = "argocd"`
- `spec.syncPolicy.automated = { prune = true, selfHeal = true }`
- `depends_on = [helm_release.argocd]`

**Known issue:** `kubernetes_manifest` validates against live CRD schema during `plan`.
`terraform validate` (static) will pass; `terraform plan` requires ArgoCD running first.
This is expected behavior, documented in nodes.md pattern.

### `gitops/apps/python-app/Application.yaml`
ArgoCD child Application pointing to the shared chart:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: python-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <var.repo_url value>   # same repo URL, literal string in YAML
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

### `gitops/apps/python-app/values.yaml`
```yaml
replicaCount: 2
image:
  repository: ""   # CI sets this via TF_VAR / yq update on push
  tag: "latest"
  pullPolicy: Always
path:
  prefix: /python-app
```
`image.repository` is intentionally empty — never hardcoded. CI/Makefile fills it.

### `gitops/apps/echo-app/Application.yaml`
Same structure as python-app, `name: echo-app`, path stays `gitops/chart`,
valueFiles points to `../apps/echo-app/values.yaml`.

### `gitops/apps/echo-app/values.yaml`
```yaml
replicaCount: 2
image:
  repository: mendhak/http-https-echo
  tag: "latest"
  pullPolicy: Always
path:
  prefix: /echo-app
```
Public image — safe to commit.

---

## Verification
```bash
terraform -chdir=infra validate   # must pass
# Inspect rendered YAML — spot-check all Application manifests exist and are valid
helm template python-app gitops/chart/ -f gitops/apps/python-app/values.yaml
helm template echo-app   gitops/chart/ -f gitops/apps/echo-app/values.yaml
```
