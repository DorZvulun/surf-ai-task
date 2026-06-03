# Plan: Expose ArgoCD UI via Traefik at localhost/argocd

## Context

ArgoCD is currently only accessible via `kubectl port-forward`, which is inconvenient for
a demo/candidate task submission. All other apps are reachable at `localhost/<path>` via
Traefik IngressRoute. ArgoCD should be no different — accessible at `localhost/argocd`
without any port-forwarding.

---

## Changes Required

### `infra/argocd.tf` — two additions

**1. Configure ArgoCD Helm release for HTTP + subpath**

Add two `set` blocks to `helm_release "argocd"`:

```hcl
set {
  name  = "server.insecure"
  value = "true"
}

set {
  name  = "server.rootpath"
  value = "/argocd"
}
```

- `server.insecure = true`: ArgoCD server serves plain HTTP (port 80). Traefik handles
  TLS at the edge — no need for ArgoCD to terminate TLS internally.
- `server.rootpath = /argocd`: ArgoCD serves its UI and API under the `/argocd` subpath.
  This makes all asset paths, redirects, and API calls relative to `/argocd`.

**2. Add Traefik IngressRoute for ArgoCD**

Append a `kubernetes_manifest` for the IngressRoute. Note: **no strip-prefix middleware**.
When `server.rootpath` is set, ArgoCD handles the subpath internally — stripping it would
break the app.

```hcl
resource "kubernetes_manifest" "argocd_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "argocd"
      namespace = "argocd"
    }
    spec = {
      entryPoints = ["web"]
      routes = [{
        match = "PathPrefix(`/argocd`)"
        kind  = "Rule"
        services = [{
          name = "argocd-server"
          port = 80
        }]
      }]
    }
  }

  depends_on = [helm_release.argocd]
}
```

`depends_on = [helm_release.argocd]` ensures the IngressRoute is created after ArgoCD is
deployed (the `argocd-server` service must exist first). Traefik CRDs are already present
from k3d startup, so there is no plan-time CRD validation issue here.

---

## Apply Impact

This change modifies the `helm_release "argocd"` values (`server.insecure`, `server.rootpath`).
If ArgoCD is already deployed, `terraform apply` will perform a Helm upgrade on the release,
which restarts the ArgoCD server pod with the new flags. Downtime is ~30 seconds.

The IngressRoute is a new resource — created fresh on apply.

---

## Verification

```bash
# After terraform apply:
curl -sf http://localhost/argocd   # should redirect to /argocd/login
```

Open `http://localhost/argocd` in browser — ArgoCD login page should load.

Login: `admin` / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
