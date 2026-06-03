# Project Tasks

Each task has one clear output, takes ≤30 minutes, and can be executed independently once its dependencies are met.

---

## Phase 1: Foundation

- [x] **Task 1** — Create public GitHub repo + initialize repo directory structure (dirs, `.gitignore`, README stub)
  - Output: all directories present, repo pushed to GitHub
  - Depends on: nothing

- [x] **Task 2** — Write `k3d-config.yaml` + `infra/main.tf` with required providers and local backend
  - Output: `terraform init` succeeds
  - Depends on: Task 1

- [x] **Task 3** — Write `infra/cluster.tf` — k3d cluster via `pvotal-tech/k3d` provider data source + kubernetes/helm providers configured from kubeconfig
  - Output: `kubectl get nodes` shows a running cluster
  - Depends on: Task 2

---

## Phase 2: Custom Python App

- [x] **Task 4** — Write `app/main.py` + `app/requirements.txt` — Flask, reads `POD_NAME`/`POD_IP` env vars, returns JSON
  - Output: `curl localhost:8080` returns `{"pod_name":"...","pod_ip":"...","app":"python-app"}`
  - Depends on: nothing (parallel with Phase 1)

- [x] **Task 5** — Write `app/Dockerfile` — simple image, port 8080
  - Output: `docker build` succeeds, container runs locally
  - Depends on: Task 4

- [x] **Task 6** — Build and push image to Docker Hub as `$DOCKERHUB_USERNAME/ironman-web-app:latest`
  - Output: image visible at `hub.docker.com/r/$DOCKERHUB_USERNAME/ironman-web-app`
  - Depends on: Task 5

---

## Phase 3: Helm Chart + ArgoCD GitOps

- [x] **Task 7** — Write `gitops/chart/` — shared Helm chart (replaces `modules/web-app/`)
  - `Chart.yaml`, `values.yaml` (defaults: replicaCount=2, image, path.prefix)
  - `templates/deployment.yaml` — with Downward API env vars (POD_NAME, POD_IP)
  - `templates/service.yaml` — ClusterIP
  - `templates/ingressroute.yaml` — Traefik IngressRoute + Middleware CRDs (`traefik.io/v1alpha1`)
  - Output: `helm template` renders valid YAML; `helm lint gitops/chart/` passes
  - Depends on: Task 3

- [x] **Task 8** — Write ArgoCD infrastructure + App-of-Apps bootstrap + per-app files
  - `infra/argocd.tf`: `kubernetes_namespace "argocd"` + `helm_release "argocd"`
  - `infra/argocd-apps.tf`: root `kubernetes_manifest` Application watching `gitops/apps/`
  - `infra/variables.tf`: `var.repo_url`, `var.docker_username`
  - `infra/terraform.tfvars`: concrete values (repo URL, docker username placeholder)
  - `gitops/apps/python-app/Application.yaml` + `values.yaml`
  - `gitops/apps/echo-app/Application.yaml` + `values.yaml`
  - Output: `terraform validate` passes; ArgoCD Application manifests are valid YAML
  - Depends on: Task 7

- [x] **Task 9** — `terraform apply` — deploy ArgoCD, ArgoCD syncs both apps, verify routing
  - Output: `curl localhost/python-app` and `curl localhost/echo-app` return pod name + IP
  - Depends on: Task 6, Task 8

---

## Phase 4: Bonus — podinfo

- [x] **Task 10** — Write `infra/podinfo.tf` — `helm_release` for podinfo + Traefik `kubernetes_manifest` IngressRoute at `/podinfo`
  - Output: `curl localhost/podinfo` returns podinfo response
  - Depends on: Task 9

---

## Phase 5: Makefile

- [ ] **Task 11** — Write `Makefile` — targets: `cluster-create`, `cluster-delete`, `build`, `init`, `plan`, `apply`, `destroy`, `test`, `all`
  - Must start with `include .secrets` + `export` to source credentials automatically
  - `apply` wraps `cluster-create` → `terraform apply`
  - `destroy` wraps `terraform destroy` → `cluster-delete`
  - `build` target uses `$(DOCKERHUB_USERNAME)/ironman-web-app:latest`
  - Output: `make all` runs end-to-end without error
  - Depends on: Task 10

---

## Phase 6: CI/CD

- [ ] **Task 12** — Write `.github/workflows/ci.yml` — `lint-and-validate` job (fmt-check, init, validate, `helm lint gitops/chart/`)
  - Output: `act push` runs lint job cleanly
  - Depends on: Task 11

- [ ] **Task 13** — Add `deploy-and-test` job to `ci.yml` — Docker build+push, update image tag in `gitops/apps/python-app/values.yaml`, git commit+push, k3d setup, apply, wait for ArgoCD sync, test, destroy
  - Output: full workflow passes with `act push --secret-file .secrets`
  - Depends on: Task 12

---

## Phase 7: Documentation

- [ ] **Task 14** — Write `README.md` — purpose, prerequisites, local setup, GitOps flow explanation, CI/CD explanation, AI usage section, design notes
  - Output: README is complete, accurate, and ready for submission
  - Depends on: Task 13

---

## Progress

10 / 14 tasks complete
