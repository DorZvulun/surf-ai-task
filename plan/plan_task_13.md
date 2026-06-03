# Task 13 — `deploy-and-test` CI job

## Context

Task 12 created `.github/workflows/ci.yml` with only the `lint-and-validate` job. Task 13
adds the full CD pipeline as a `deploy-and-test` job. Three categories of change each have
a defined CI response:

| Change type | CI response |
|---|---|
| `app/**` | Build+push image, update tag, deploy, test, destroy |
| `infra/**` or `gitops/**` | Deploy with existing image, test, destroy (no build) |
| Docs / other | Skip deploy entirely — lint is enough |
| echo-app / podinfo | ArgoCD handles these via git — no CI build needed (public images) |

Infra changes use an ephemeral create→test→destroy cycle (no blue-green). Port 80/443 on
localhost can't be shared between two clusters without a proxy layer — that's a production
concern (DNS/LB switchover) out of scope for this assignment. The README will note this.

---

## Single file to modify

**`.github/workflows/ci.yml`** — append one new job: `deploy-and-test`

---

## Job design

```yaml
deploy-and-test:
  needs: lint-and-validate
  runs-on: ubuntu-24.04
  if: github.event_name == 'push'
```

- `needs: lint-and-validate` — CD only runs if linting passes.
- `if: github.event_name == 'push'` — skips on PRs.
- Path filtering via `dorny/paths-filter` (added as the first step of `lint-and-validate`)
  determines whether the deploy job actually proceeds.

---

## Path filtering — how it works

Add a `dorny/paths-filter@v3` step to `lint-and-validate` and expose its output:

```yaml
lint-and-validate:
  runs-on: ubuntu-24.04
  outputs:
    app_changed: ${{ steps.filter.outputs.app }}
    deploy_needed: ${{ steps.filter.outputs.deploy }}
  steps:
    - uses: actions/checkout@v4

    - uses: dorny/paths-filter@v3
      id: filter
      with:
        filters: |
          app:
            - 'app/**'
          deploy:
            - 'app/**'
            - 'infra/**'
            - 'gitops/**'
            - 'k3d-config.yaml'
```

The `deploy-and-test` job then gates on:

```yaml
if: github.event_name == 'push' && needs.lint-and-validate.outputs.deploy_needed == 'true'
```

Inside the job, the Docker build+push steps have an additional condition:

```yaml
if: needs.lint-and-validate.outputs.app_changed == 'true'
```

---

## Full step list for `deploy-and-test`

| # | Step | Condition | Action |
|---|------|-----------|--------|
| 1 | Checkout | always | `actions/checkout@v4` |
| 2 | Docker Buildx | `app_changed` | `docker/setup-buildx-action@v3` |
| 3 | Docker Hub login | `app_changed` | `docker/login-action@v3` with secrets |
| 4 | Build & push image | `app_changed` | `docker/build-push-action@v5` — tags `${{ github.sha }}` + `latest` |
| 5 | Update image tag | `app_changed` | Install `yq`, run `yq -i '.image.tag = "..."'` on `gitops/apps/python-app/values.yaml` |
| 6 | Commit & push | `app_changed` | `git config` bot user, commit, push |
| 7 | Install k3d | always | Official install script from raw.githubusercontent.com |
| 8 | Setup Terraform | always | `hashicorp/setup-terraform@v3` |
| 9 | Create `.secrets` | always | Write `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` from CI secrets — required by Makefile `include .secrets` |
| 10 | `make init` | always | `terraform -chdir=infra init` |
| 11 | `make apply` | always | Creates k3d cluster then `terraform apply -auto-approve` |
| 12 | Wait for ArgoCD sync | always | `kubectl -n argocd wait --for=condition=Synced application/python-app --timeout=120s` |
| 13 | `make test` | always | `curl -fsL` all three routes |
| 14 | `make destroy` | `if: always()` | `terraform destroy` + `k3d cluster delete` |

"always" here means "whenever this job runs" (the job itself is already gated by path filters).

---

## Key implementation details

**`.secrets` file**: Makefile starts with `include .secrets` / `export`, so every `make`
command fails without the file. Step 9 writes it before any `make` call:
```bash
echo "DOCKERHUB_USERNAME=${{ secrets.DOCKERHUB_USERNAME }}" > .secrets
echo "DOCKERHUB_TOKEN=${{ secrets.DOCKERHUB_TOKEN }}" >> .secrets
```

**yq**: Not pre-installed on ubuntu-24.04. Download binary:
```bash
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
yq -i ".image.tag = \"${{ github.sha }}\"" gitops/apps/python-app/values.yaml
```

**git push**: Use `GITHUB_TOKEN` (default from `actions/checkout@v4`). Configure bot identity:
```bash
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
```

**Conditional steps in GitHub Actions**: Steps without native `if` support (like
`docker/build-push-action`) are gated by wrapping in a condition referencing the
`lint-and-validate` job output:
```yaml
if: needs.lint-and-validate.outputs.app_changed == 'true'
```

**Destroy always runs**: `if: always()` on step 14 guarantees cluster cleanup even if
earlier steps fail, preventing orphaned k3d clusters on the runner.

---

## README note (Task 14 scope)

Add a brief note under the CI/CD section:
> Infra changes use an ephemeral test cluster (create → test → destroy). Zero-downtime
> blue-green at this level would require a reverse proxy to manage port switchover between
> clusters — the production equivalent is a DNS/load-balancer cutover, which is out of scope
> for a local k3d setup.

---

## Critical files

| File | Change |
|---|---|
| `.github/workflows/ci.yml` | (1) Add `outputs:` + `paths-filter` step to `lint-and-validate`; (2) append full `deploy-and-test` job |

---

## Verification

```bash
# Local — requires .secrets with valid DOCKERHUB creds and Docker running
act push --secret-file .secrets

# Expected: lint-and-validate runs first; deploy-and-test follows only if
# app/**, infra/**, gitops/**, or k3d-config.yaml changed in the pushed commit.
# If only README.md changed, deploy-and-test is skipped entirely.
```
