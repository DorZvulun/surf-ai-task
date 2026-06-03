# Plan: Task 9 — terraform apply → ArgoCD live → Verify Routing

## Context

Tasks 7–8 produced the Helm chart (`gitops/chart/`) and ArgoCD Terraform config
(`infra/argocd.tf`, `infra/argocd-apps.tf`). Task 9 brings everything live: create the
k3d cluster, run `terraform apply`, wait for ArgoCD to sync both apps, and curl the
routes to confirm routing works.

**Expected outcome:** `curl localhost/echo-app` returns HTTP 200 with an echo JSON body.
python-app will be Degraded (empty `image.repository`) — that is expected and intentional;
it gets fixed by CI in Task 12–13.

---

## Code Changes Required

### 1. `infra/argocd.tf` — add `wait = true`

**Why:** Without `wait = true`, Terraform marks `helm_release.argocd` complete as soon as
Helm accepts the request, then immediately tries to apply `kubernetes_manifest "argocd_root_app"`
from `argocd-apps.tf`. At that point ArgoCD's CRDs (`argoproj.io/v1alpha1`) may not yet be
registered, causing: _no matches for kind "Application" in group "argoproj.io"_.

`wait = true` makes Terraform block until all ArgoCD pods are Running and CRDs are registered.

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  wait       = true          # ← add this line

  depends_on = [kubernetes_namespace.argocd]
}
```

### 2. `infra/outputs.tf` — new file

Provides a post-apply hint for retrieving the ArgoCD admin password (needed for UI/CLI login during verification).

```hcl
output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_admin_password_cmd" {
  value     = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive = false
}
```

---

## Apply Sequence (operational — no more code changes after above)

```bash
# 1. Create cluster (k3d-config.yaml: 1 server + 1 agent, ports 80/443)
k3d cluster create surf-cluster --config k3d-config.yaml

# 2. Apply — creates: argocd namespace → ArgoCD helm release (waits for CRDs ready)
#    → root App-of-Apps Application
terraform -chdir=infra apply -auto-approve

# 3. Wait for ArgoCD to sync echo-app (python-app will be Degraded — expected)
kubectl -n argocd wait --for=condition=Synced application/echo-app --timeout=180s

# 4. Verify echo-app routing
curl -sf localhost/echo-app | head -20

# 5. Confirm python-app is Degraded (not a failure — image.repository is intentionally empty)
kubectl -n argocd get app python-app
```

---

## Verification Checklist

| Check | Command | Expected |
|---|---|---|
| Cluster up | `kubectl get nodes` | 2 nodes Ready |
| ArgoCD pods | `kubectl -n argocd get pods` | all Running |
| Root app | `kubectl -n argocd get app apps` | Synced/Healthy |
| echo-app | `kubectl -n argocd get app echo-app` | Synced/Healthy |
| echo routing | `curl -sf localhost/echo-app` | HTTP 200, echo JSON |
| python-app | `kubectl -n argocd get app python-app` | Degraded (expected) |

---

## Teardown (after verification)

```bash
terraform -chdir=infra destroy -auto-approve
k3d cluster delete surf-cluster
```
