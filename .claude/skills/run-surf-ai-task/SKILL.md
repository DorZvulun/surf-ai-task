---
name: run-surf-ai-task
description: run, start, build, deploy, test, smoke-test, screenshot, verify surf-ai-task — k3d cluster with ArgoCD GitOps and three apps exposed via Traefik
---

# run-surf-ai-task

This is a Kubernetes infrastructure project, not a GUI app. The "app" surface is three HTTP
endpoints served by Traefik on `localhost:80` inside a k3d cluster. The driver is
`.claude/skills/run-surf-ai-task/smoke.sh` — a `curl`-based smoke test. All paths below
are relative to the repo root.

---

## Prerequisites

All must be installed on the host machine:

```
docker, k3d, kubectl, helm, terraform
```

Credentials live in `.secrets` (gitignored):

```
DOCKERHUB_USERNAME=<your-username>
DOCKERHUB_TOKEN=<your-token>
```

---

## Build (ironman-web-app only)

The other two apps use public images. The ironman-web-app must be built and pushed once before
it can be deployed by ArgoCD:

```bash
make build
```

This builds `$DOCKERHUB_USERNAME/ironman-web-app:latest`, pushes it, patches
`gitops/apps/ironman-web-app/values.yaml` with the correct `image.repository`, and commits +
pushes the change so ArgoCD can pick it up.

**Until `make build` is run**, ironman-web-app pods show `InvalidImageName` and the endpoint
returns 503. The other two apps (echo-app, podinfo) are unaffected.

---

## Full stack bring-up

```bash
make init    # terraform init
make apply   # k3d cluster create → terraform apply (deploys ArgoCD + App-of-Apps)
```

Wait for ArgoCD to sync all apps (~60–120 s):

```bash
kubectl -n argocd wait --for=condition=Synced application/echo-app --timeout=120s
kubectl -n argocd wait --for=condition=Synced application/podinfo   --timeout=120s
# only if make build was run first:
kubectl -n argocd wait --for=condition=Synced application/ironman-web-app --timeout=120s
```

---

## Run (agent path) — smoke test

```bash
# With ironman-web-app (requires make build first):
bash .claude/skills/run-surf-ai-task/smoke.sh

# Without ironman-web-app (echo-app + podinfo only):
SKIP_PYTHON_APP=1 bash .claude/skills/run-surf-ai-task/smoke.sh
```

Expected output (verified 2026-06-03 on arm64 macOS, cluster surf-cluster):

```
=== surf-ai-task smoke test ===
PASS  echo-app  →  { "path": "/", "headers": { "host": "localhost", ...
PASS  podinfo   →  { "hostname": "podinfo-fc49f998d-lpqqj", "version": "6.12.0", ...
Results: 2 passed, 0 failed
```

The script exits non-zero if any checked route returns non-200.

---

## Run (human path)

```bash
make test    # same curl checks, prints response bodies
```

---

## Tear down

```bash
make destroy    # terraform destroy → k3d cluster delete
```

---

## Gotchas

- **`image.repository: ""`** — ironman-web-app `values.yaml` ships with an empty repository
  field. ArgoCD will sync successfully but pods fail with `InvalidImageName`. Fix:
  `make build`. echo-app and podinfo are unaffected.

- **ArgoCD sync lag** — after `make apply` the ArgoCD operator takes 60–90 s to pick up
  the root App-of-Apps and create child Applications. `kubectl -n argocd get applications`
  will show nothing for the first minute. Use `--timeout=120s` on the wait commands.

- **`make apply` is NOT idempotent for the cluster** — `cluster-create` runs
  `k3d cluster create`, which errors if `surf-cluster` already exists. If the cluster is
  already up, run `terraform -chdir=infra apply -auto-approve` directly instead.

- **Traefik strip-prefix** — all apps are routed with a strip-prefix middleware, so the
  upstream app sees `/` not `/echo-app`. The echo-app response will show `"path": "/"`.

- **`sed -i ''` in Makefile** — macOS syntax. CI uses `yq`. Do not run `make build` on
  Linux without adjusting the sed invocation.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `curl: (22) ... 503` on ironman-web-app | Run `make build` first |
| `k3d cluster create` fails: cluster already exists | Run `k3d cluster delete surf-cluster` first, or skip to `terraform apply` |
| ArgoCD Applications not appearing | Wait 90 s after `make apply`; ArgoCD startup takes ~60 s |
| `InvalidImageName` pods stuck after `make build` | ArgoCD needs to re-sync; trigger with `argocd app sync ironman-web-app` or wait ~3 min |
| `terraform apply` fails: `connection refused` | k3d cluster isn't up yet; run `k3d cluster list` and wait for `1/1` servers |
