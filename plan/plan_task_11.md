# Plan: Task 11 — Write Makefile

## Context

Tasks 1–10 are complete. The cluster, ArgoCD, and all three apps (python-app, echo-app, podinfo) are working. The `Makefile` is the missing automation glue that ties together Docker build, Terraform, k3d lifecycle, and end-to-end smoke testing. It must also patch `gitops/apps/python-app/values.yaml` with the correct `image.repository` (currently empty `""`) so that `make all` can run successfully end-to-end.

---

## File to Create

**`/Users/dorzvulun/repos/Obsidian/surf-ai-task/Makefile`** (new file)

---

## Makefile Design

### Credential sourcing

```makefile
include .secrets
export

TF_VAR_docker_username := $(DOCKERHUB_USERNAME)
IMAGE := $(DOCKERHUB_USERNAME)/ironman-web-app
```

- `include .secrets` + `export` makes `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` available as env vars to every recipe.
- `TF_VAR_docker_username` is explicitly set so Terraform picks up `var.docker_username` without the user needing to set it separately.
- `IMAGE` is a convenience variable to avoid repeating `$(DOCKERHUB_USERNAME)/ironman-web-app`.

---

### Targets

| Target | Recipe |
|---|---|
| `cluster-create` | `k3d cluster create --config k3d-config.yaml` |
| `cluster-delete` | `k3d cluster delete surf-cluster` |
| `build` | docker build + push; then patch `values.yaml` with correct `image.repository` via `sed` and git commit+push so ArgoCD can deploy |
| `init` | `terraform -chdir=infra init` |
| `plan` | `terraform -chdir=infra plan` |
| `apply` | depends on `cluster-create`, then `terraform -chdir=infra apply -auto-approve` |
| `destroy` | `terraform -chdir=infra destroy -auto-approve`, then `$(MAKE) cluster-delete` |
| `test` | `curl -fs` each of the three routes; `-f` exits non-zero on HTTP error |
| `all` | `build init apply test` (in order) |

---

### `build` target detail

The `python-app/values.yaml` has `image.repository: ""`. ArgoCD cannot deploy without the correct registry path. The `build` step must patch it:

```makefile
build:
	docker build -t $(IMAGE):latest app/
	docker push $(IMAGE):latest
	sed -i '' 's|repository:.*|repository: $(IMAGE)|' gitops/apps/python-app/values.yaml
	git add gitops/apps/python-app/values.yaml
	git diff --cached --quiet || git commit -m "[ci] update python-app image repository"
	git push || true
```

- `sed -i ''` is macOS syntax (matches the dev machine). CI uses its own `yq`-based step.
- `git diff --cached --quiet || git commit` skips the commit if the file didn't change (idempotent).
- `git push || true` is best-effort — if upstream is already at HEAD it won't fail the build.

---

### `test` target detail

```makefile
test:
	@echo "--- python-app ---" && curl -fsL localhost/python-app && echo
	@echo "--- echo-app ---"   && curl -fsL localhost/echo-app   && echo
	@echo "--- podinfo ---"    && curl -fsL localhost/podinfo     && echo
```

`-f` → non-zero exit on HTTP error (4xx/5xx)  
`-s` → suppress progress bar  
`-L` → follow redirects  
Each `echo` adds a newline after the JSON body for readability.

---

### `destroy` target detail

Order matters: Terraform destroy removes ArgoCD + k3d TF resources first, then `cluster-delete` removes the actual k3d cluster. This avoids the TF provider trying to reach a deleted cluster.

---

## Verification

After implementation:

1. `make cluster-create` — k3d cluster comes up; `kubectl get nodes` shows 2 nodes.
2. `make build` — image pushed to Docker Hub; `values.yaml` updated and committed.
3. `make init` — `terraform init` succeeds.
4. `make apply` — ArgoCD deployed; apps synced.
5. `make test` — all three `curl` calls return 200 and print JSON/response bodies.
6. `make destroy` — cluster torn down cleanly.
7. `make all` — full end-to-end run without error.
