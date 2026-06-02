# Plan: Task 9 — `terraform apply` → ArgoCD Live → Verify Routing

## Context

Tasks 7–8 created the Helm chart and ArgoCD Terraform config. Task 9 brings everything live:
create the k3d cluster, run `terraform apply`, wait for ArgoCD to sync both apps, and verify
routing via curl. One code fix is needed before apply works reliably.

**Dependency note:** python-app requires a real Docker image (`image.repository` is currently
`""` — set by CI in Task 6). Until Task 6 is done, only echo-app will reach Healthy/Synced.
Task 9 is verifiable with echo-app alone; python-app verification follows after Task 6.

---

## Code Change Required Before Apply

### `infra/argocd.tf` — add `wait = true`

Without it, Terraform moves on to applying `kubernetes_manifest "argocd_root_app"` while
ArgoCD CRDs (`argoproj.io/v1alpha1`) may not yet be registered, causing a "no matches for
kind Application" error.

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  wait       = true          # ← add this

  depends_on = [kubernetes_namespace.argocd]
}
```

### `infra/outputs.tf` — new file

Needed to retrieve the ArgoCD initial admin password after apply.

```hcl
output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_initial_admin_secret" {
  value     = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive = false
}
```

---

## Apply Sequence (operational — no more code changes)

```bash
# 1. Create cluster (k3d-config.yaml: 1 server + 1 agent, ports 80/443)
k3d cluster create surf-cluster --config k3d-config.yaml

# 2. Init providers (first time on this machine)
terraform -chdir=infra init

# 3. Apply — creates: argocd namespace, ArgoCD helm release (waits for ready),
#    then root App-of-Apps Application
terraform -chdir=infra apply -auto-approve

# 4. Wait for ArgoCD to sync echo-app (python-app will be Degraded until Task 6)
kubectl -n argocd wait --for=condition=Synced application/echo-app --timeout=180s

# 5. Verify echo-app routing
curl -sf localhost/echo-app | head -20

# 6. (After Task 6) update python-app values.yaml image.repository, push → ArgoCD syncs
#    curl -sf localhost/python-app
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
| python-app | after Task 6 — `curl -sf localhost/python-app` | `{"pod_name":...}` |

---

## Teardown (after verification)
```bash
terraform -chdir=infra destroy -auto-approve
k3d cluster delete surf-cluster
```
