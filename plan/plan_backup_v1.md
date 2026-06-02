# Project Task Schedule — Terraform K8s Candidate Task

## Context

Senior DevOps take-home assignment. Full plan and tech decisions are locked in CLAUDE.md.
This file is the execution schedule — ordered tasks, each ≤30 minutes.

## Definition of a Task

A task is a single, independently verifiable unit of work:
- Has one clear output (a file, a passing curl, a pushed image)
- Takes ≤30 minutes
- Can be handed to Claude Code as a self-contained prompt
- Blocked by prior tasks only when there is a hard dependency

---

## Task Schedule

### Phase 1: Foundation

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 1 | Create public GitHub repo + initialize local repo structure (dirs, .gitignore, README stub) | Repo exists, all directories present | 15m | — |
| 2 | Write `k3d-config.yaml` + `infra/main.tf` with required providers and local backend | `terraform init` succeeds | 20m | 1 |
| 3 | Write `infra/cluster.tf` — k3d cluster via `pvotal-tech/k3d` provider + configure kubernetes/helm providers from cluster kubeconfig | `kubectl get nodes` shows cluster | 25m | 2 |

### Phase 2: Custom App

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 4 | Write Python app: `app/main.py`, `app/requirements.txt` — Flask, reads `POD_NAME`/`POD_IP` env vars, returns JSON | `curl localhost:8080` returns `{"pod_name":"...","pod_ip":"..."}` | 20m | — |
| 5 | Write `app/Dockerfile` — simple, small image, port 8080 | `docker build` succeeds, container runs locally | 15m | 4 |
| 6 | Build and push image to Docker Hub as `DOCKER_USERNAME/APP_IMAGE_NAME:latest` | Image visible on Docker Hub | 10m | 5 |

### Phase 3: Terraform Module + Routing

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 7 | Write `modules/web-app/` — Deployment (with Downward API), Service, Traefik IngressRoute + strip-prefix Middleware | Module files written, `terraform validate` passes | 25m | 3 |
| 8 | Write `infra/apps.tf`, `infra/variables.tf`, `infra/terraform.tfvars` — define both apps, instantiate module via `for_each` | `terraform plan` shows correct resources | 20m | 7 |
| 9 | `terraform apply` — deploy both apps, verify routing | `curl localhost/python-app` and `curl localhost/echo-app` return pod name + IP | 20m | 6, 8 |

### Phase 4: Bonus

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 10 | Write `infra/podinfo.tf` — `helm_release` for podinfo + Traefik IngressRoute at `/podinfo` | `curl localhost/podinfo` returns podinfo UI | 20m | 9 |

### Phase 5: Makefile + Local CI

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 11 | Write `Makefile` — all targets: `build`, `init`, `plan`, `apply`, `destroy`, `test`, `all` | `make all` runs end-to-end without error | 20m | 10 |

### Phase 6: CI/CD

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 12 | Write `.github/workflows/ci.yml` — `lint-and-validate` job (fmt-check, init, validate) | `act push` runs lint job cleanly | 20m | 11 |
| 13 | Add `deploy-and-test` job to `ci.yml` — Docker build+push, k3d setup, apply, test, destroy | Full workflow passes with `act push` | 25m | 12 |

### Phase 7: Documentation

| # | Task | Output | Time | Depends on |
|---|---|---|---|---|
| 14 | Write `README.md` — purpose, prerequisites, local setup steps, CI/CD explanation, AI usage section, design notes | README is complete and accurate | 25m | 13 |

---

## Total

14 tasks × avg 20m = ~4.5 hours wall-clock (some parallel: task 4+5 can run while waiting on task 3)

---

## Verification (end-to-end)

```bash
make all                    # build → init → apply → test
curl localhost/python-app   # {"pod_name":"...","pod_ip":"...","app":"python-app"}
curl localhost/echo-app     # echo response with POD_NAME/POD_IP env vars
curl localhost/podinfo      # podinfo web UI
make destroy                # clean teardown
act push --secret-file .secrets  # full CI run locally
```
