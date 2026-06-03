# Task 12 — CI `lint-and-validate` job

## Context

Task 12 is the first CI/CD task in the project. The goal is to create `.github/workflows/ci.yml`
with a `lint-and-validate` job that catches formatting/syntax errors in Terraform and the shared
Helm chart before any deployment happens. Task 13 will add the `deploy-and-test` job to the same
file. The `.github/workflows/` directory exists with only a `.gitkeep` — nothing to migrate.

## What to create

**Single file:** `.github/workflows/ci.yml`

## Workflow design

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint-and-validate:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform fmt check
        run: terraform -chdir=infra fmt -check

      - name: Terraform init
        run: terraform -chdir=infra init

      - name: Terraform validate
        run: terraform -chdir=infra validate

      - name: Setup Helm
        uses: azure/setup-helm@v4

      - name: Helm lint
        run: helm lint gitops/chart/
```

## Key decisions

- **Trigger**: both `push` and `pull_request` to `main` — lint should gate PRs too.
- **`hashicorp/setup-terraform@v3`**: latest stable; no version pin needed — validate doesn't run plan or apply.
- **`azure/setup-helm@v4`**: standard community action for Helm setup.
- **No secrets required**: `terraform init` downloads providers from the registry (including `pvotal-tech/k3d`); `terraform validate` checks syntax only — no cluster needed, no variable values needed.
- **`deploy-and-test` job**: intentionally omitted — that is Task 13. The file is structured so it can be added in the next task.

## Critical files

| File | Action |
|---|---|
| `.github/workflows/ci.yml` | Create (new file) |

## Verification

```bash
# Local: test workflow with act
act push --secret-file .secrets

# Or just verify the YAML is well-formed:
helm lint gitops/chart/
terraform -chdir=infra fmt -check
terraform -chdir=infra init
terraform -chdir=infra validate
```

The `act push` run should show the `lint-and-validate` job succeeding end-to-end with no failures.
