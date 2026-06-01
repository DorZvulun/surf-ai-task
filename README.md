# Senior DevOps Candidate Task

Provision a local Kubernetes cluster using Terraform, deploy multiple web applications via a reusable module, expose them through an API gateway with distinct routes, and build a CI/CD pipeline.

## Stack

- **Local K8s**: k3d (via `pvotal-tech/k3d` Terraform provider)
- **Ingress / API Gateway**: Traefik (built into k3d)
- **IaC**: Terraform with reusable modules
- **Custom App**: Python Flask → Docker Hub
- **CI/CD**: GitHub Actions

## Quick Start

```bash
# Prerequisites: Docker, terraform, k3d, kubectl, helm
# Populate .secrets with DOCKERHUB_USERNAME and DOCKERHUB_TOKEN

make build    # Build and push Python app image
make init     # terraform init
make apply    # Provision cluster + deploy all apps
make test     # Verify all routes return HTTP 200
make destroy  # Tear down cluster
```

## Endpoints

| Path | App |
|------|-----|
| `localhost/python-app` | Custom Python Flask app |
| `localhost/echo-app` | mendhak/http-https-echo |
| `localhost/podinfo` | podinfo (Helm, bonus) |

## AI Usage

Claude Code (claude-sonnet-4-6) assisted with this task. Architecture decisions were made collaboratively — human confirmed every tech choice before code was written. Claude generated TF modules, Python app, Dockerfile, and CI workflow; human reviewed all output before committing.
