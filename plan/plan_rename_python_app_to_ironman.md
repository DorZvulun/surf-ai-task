# Plan — Rename `python-app` → `ironman-web-app`

## Goal

Align the ArgoCD Application name, K8s resource names, repo folder, and route URL with
the real Docker image name `ironman-web-app`. After this change:

- `kubectl -n argocd get applications` shows `ironman-web-app` (not `python-app`)
- `kubectl get deploy,svc,ingressroute` shows `ironman-web-app`, `ironman-web-app-svc`,
  `ironman-web-app-ingressroute` (driven by Helm release name)
- `gitops/apps/ironman-web-app/` is the repo folder
- `curl localhost/ironman-web-app` is the working URL
- The JSON `app` field returns `"ironman-web-app"`

The image name `$DOCKERHUB_USERNAME/ironman-web-app` is already correct and unchanged.

---

## Why this is safe to do as one rename

`python-app` is the Helm release name (`metadata.name` in the ArgoCD `Application`).
Every K8s object is derived from it via the chart's `{{ .Release.Name }}-<type>` pattern.
Renaming the Application → ArgoCD deletes the old K8s objects and creates new ones on
the next sync. No data is at stake (stateless pods). Route URL changes are a deliberate
UX change the user has confirmed.

---

## Scope — files to change

### 1. Repo folder rename
- `gitops/apps/python-app/` → `gitops/apps/ironman-web-app/`
  - Move via `git mv` so history is preserved.
  - Contents (`Application.yaml`, `values.yaml`) move with edits in step 2.

### 2. ArgoCD Application & values (the source of truth)
- `gitops/apps/ironman-web-app/Application.yaml`
  - `metadata.name: python-app` → `ironman-web-app`
  - `spec.source.helm.valueFiles[0]`: `../apps/python-app/values.yaml` →
    `../apps/ironman-web-app/values.yaml`
- `gitops/apps/ironman-web-app/values.yaml`
  - `path.prefix: /python-app` → `/ironman-web-app`
  - `image.repository` is already set correctly — no change needed.

### 3. Python app response payload
- `app/main.py` — `app="python-app"` → `app="ironman-web-app"`
  - Cosmetic only (the JSON body identifier). Triggers a new image build, so CI will
    rebuild and push under the same `ironman-web-app` image name with the new SHA tag.

### 4. Makefile
- `build` target: `sed` and `git add` paths → `gitops/apps/ironman-web-app/values.yaml`
- `test` target: `curl -fsL localhost/python-app` → `localhost/ironman-web-app`
  and the echo label `--- python-app ---` → `--- ironman-web-app ---`

### 5. GitHub Actions workflow (`.github/workflows/ci.yml`)

All occurrences of `python-app` in the file:

| Step | Change |
|---|---|
| `Update python-app image tag` (step name) | → `Update ironman-web-app image tag` |
| `yq -i ... gitops/apps/python-app/values.yaml` | → `.../ironman-web-app/values.yaml` |
| `git add gitops/apps/python-app/values.yaml` | → `.../ironman-web-app/values.yaml` |
| `[ci] update python-app image to ${SHA}` (commit msg) | → `ironman-web-app` |
| `Wait for ArgoCD apps to be created` — `for app in python-app echo-app podinfo` | → `ironman-web-app echo-app podinfo` |
| `Wait for ArgoCD sync` — `for app in python-app echo-app podinfo` | → `ironman-web-app echo-app podinfo` |
| `Wait for deployments to be ready` — `kubectl rollout status deployment/python-app` | → `deployment/ironman-web-app` |

### 6. Documentation (consistency only — no functional impact)
- `README.md` — all `python-app` references (URLs, ArgoCD output examples, folder paths,
  architecture diagrams).
- `CLAUDE.md` — all `python-app` references. Note: image name `ironman-web-app` on
  line 193 is already correct — leave unchanged.
- `TASKS.md` — lines 26, 54, 60, 91.

---

## Execution order (one PR)

1. `git mv gitops/apps/python-app gitops/apps/ironman-web-app`
2. Edit the 2 yaml files inside the renamed folder (step 2 above).
3. Edit `app/main.py` (step 3).
4. Edit `Makefile` (step 4).
5. Edit `.github/workflows/ci.yml` (step 5).
6. Update docs `README.md`, `CLAUDE.md`, `TASKS.md` (step 6).
7. `terraform -chdir=infra fmt -check` — should pass unchanged (no `.tf` files touched).
8. `helm lint gitops/chart/` — should pass unchanged (chart itself is generic).
9. Commit as a single change: `rename python-app → ironman-web-app`.

---

## What is intentionally NOT changing

- The shared Helm chart (`gitops/chart/`) — already generic, named only via `Release.Name`.
- The Docker image name `ironman-web-app` — already correct.
- Terraform files in `infra/` — no `python-app` references (apps are owned by ArgoCD).
- `gitops/apps/echo-app/` and `gitops/apps/podinfo/` — unrelated apps.
- The root App-of-Apps ArgoCD Application (it watches the `gitops/apps/` directory and
  auto-discovers children — folder rename is transparent to it).

---

## Verification after applying

```bash
# After merge + ArgoCD sync:
kubectl -n argocd get applications
# Expect: ironman-web-app  Synced  Healthy   (no python-app)

kubectl get deploy,svc
# Expect: deployment.apps/ironman-web-app
#         service/ironman-web-app-svc

kubectl get ingressroute
# Expect: ironman-web-app-ingressroute

curl -fsL localhost/ironman-web-app
# Expect: {"pod_name":"ironman-web-app-...","pod_ip":"...","app":"ironman-web-app"}

curl -fsI localhost/python-app
# Expect: 404 (route gone)

make test
# Expect: all three apps pass (ironman-web-app, echo-app, podinfo)
```

---

## Rollout consideration (informational)

During the first ArgoCD sync after this change, the old `python-app` Application will be
pruned (deleted from the cluster) and the new `ironman-web-app` Application will be
created. Brief 404 window on the old `/python-app` route is expected — acceptable for
this assignment. If we wanted zero-downtime in a real environment, we'd run both routes
in parallel for one release cycle, then remove the old one — but that's out of scope.
