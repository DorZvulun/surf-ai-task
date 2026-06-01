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

- [ ] **Task 3** — Write `infra/cluster.tf` — k3d cluster via `pvotal-tech/k3d` provider + configure kubernetes/helm providers from cluster kubeconfig
  - Output: `kubectl get nodes` shows a running cluster
  - Depends on: Task 2

---

## Phase 2: Custom Python App

- [ ] **Task 4** — Write `app/main.py` + `app/requirements.txt` — Flask, reads `POD_NAME`/`POD_IP` env vars, returns JSON
  - Output: `curl localhost:8080` returns `{"pod_name":"...","pod_ip":"...","app":"python-app"}`
  - Depends on: nothing (parallel with Phase 1)

- [ ] **Task 5** — Write `app/Dockerfile` — simple image, port 8080
  - Output: `docker build` succeeds, container runs locally
  - Depends on: Task 4

- [ ] **Task 6** — Build and push image to Docker Hub as `$DOCKERHUB_USERNAME/ironman-web-app:latest`
  - Output: image visible at `hub.docker.com/r/$DOCKERHUB_USERNAME/ironman-web-app`
  - Depends on: Task 5

---

## Phase 3: Terraform Module + Routing

- [ ] **Task 7** — Write `modules/web-app/` — Deployment (Downward API), Service, Traefik IngressRoute + strip-prefix Middleware
  - Output: module files written, `terraform validate` passes
  - Depends on: Task 3

- [ ] **Task 8** — Write `infra/apps.tf`, `infra/variables.tf`, `infra/terraform.tfvars` — define both apps, instantiate module via `for_each`
  - `variables.tf` includes `variable "docker_username" {}`
  - `apps.tf` constructs python-app image as `"${var.docker_username}/ironman-web-app:latest"`
  - `docker_username` never in tfvars — injected via `TF_VAR_docker_username` env var from `.secrets`
  - Output: `terraform plan` shows correct resources
  - Depends on: Task 7

- [ ] **Task 9** — `terraform apply` — deploy both apps, verify routing
  - Output: `curl localhost/python-app` and `curl localhost/echo-app` return pod name + IP
  - Depends on: Task 6, Task 8

---

## Phase 4: Bonus — podinfo

- [ ] **Task 10** — Write `infra/podinfo.tf` — `helm_release` for podinfo + Traefik IngressRoute at `/podinfo`
  - Output: `curl localhost/podinfo` returns podinfo response
  - Depends on: Task 9

---

## Phase 5: Makefile

- [ ] **Task 11** — Write `Makefile` — targets: `build`, `init`, `plan`, `apply`, `destroy`, `test`, `all`
  - Must start with `include .secrets` + `export` to source credentials automatically
  - `build` target uses `$(DOCKERHUB_USERNAME)/ironman-web-app:latest`
  - Output: `make all` runs end-to-end without error
  - Depends on: Task 10

---

## Phase 6: CI/CD

- [ ] **Task 12** — Write `.github/workflows/ci.yml` — `lint-and-validate` job (fmt-check, init, validate)
  - Output: `act push` runs lint job cleanly
  - Depends on: Task 11

- [ ] **Task 13** — Add `deploy-and-test` job to `ci.yml` — Docker build+push, k3d setup, apply, test, destroy
  - Output: full workflow passes with `act push --secret-file .secrets`
  - Depends on: Task 12

---

## Phase 7: Documentation

- [ ] **Task 14** — Write `README.md` — purpose, prerequisites, local setup, CI/CD explanation, AI usage section, design notes
  - Output: README is complete, accurate, and ready for submission
  - Depends on: Task 13

---

## Progress

2 / 14 tasks complete
