The move to v2 - ArgoCD / App-of-Apps / gitops, Seperating Infra from App
 ---
  Removed from v1.1

  ┌──────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                 What                 │                                             Detail                                              │
  ├──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ modules/web-app/ Terraform module    │ The reusable TF module for Deployment + Service + IngressRoute is deleted entirely              │
  ├──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ infra/apps.tf                        │ The for_each-based module instantiation file is gone                                            │
  ├──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ apps map in terraform.tfvars         │ The per-app variable block is removed; Terraform no longer owns app definitions                 │
  ├──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Terraform managing K8s app lifecycle │ TF no longer creates kubernetes_deployment, kubernetes_service, or kubernetes_manifest for apps │
  ├──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Task 8 (old): write apps.tf + tfvars │ Replaced with a completely different task                                                       │
  └──────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  Added in v2

  ┌──────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                     What                     │                                                       Detail                                                       │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ArgoCD                                       │ Deployed via helm_release in infra/argocd.tf; becomes the app deployment engine                                    │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ App-of-Apps pattern                          │ One root ArgoCD Application (in infra/argocd-apps.tf) watches gitops/apps/                                         │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ gitops/chart/                                │ A shared Helm chart that replaces modules/web-app/ — same concepts (Deployment, Service, Traefik CRDs) but in Helm │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ gitops/apps/<name>/                          │ Per-app Application.yaml + values.yaml — adding an app = adding 2 files, zero Terraform changes                    │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ var.repo_url                                 │ New variable so ArgoCD knows where to pull chart/values from                                                       │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ CI image-tag git commit step                 │ After Docker push, CI updates values.yaml with the git SHA and pushes — ArgoCD auto-detects and rolls              │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ make cluster-create / cluster-delete targets │ Explicit cluster lifecycle targets in Makefile                                                                     │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ helm lint in CI lint job                     │ Task 12 now validates the Helm chart too                                                                           │
  ├──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ArgoCD verification steps                    │ Verification now includes checking kubectl get applications -n argocd and a GitOps scale test                      │
  └──────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  Core shift: v1.1 had Terraform owning the full app lifecycle end-to-end. v2 splits responsibility — Terraform only provisions infrastructure (cluster + ArgoCD), and ArgoCD takes over everything app-related via Git as the source of truth.




  what tasks can run at parralel so I can use several sessions to handle them in parralle?

⏺ Looking at the dependency graph from TASKS.md:

  Tasks 1-3 ✓ done

  RIGHT NOW — two sessions can run in parallel:

    Session A                 Session B
    ─────────                 ─────────
    Task 4 (app/main.py)      Task 7 (gitops/chart/ Helm chart)
      ↓                         ↓
    Task 5 (Dockerfile)       Task 8 (argocd.tf + argocd-apps.tf
      ↓                              + per-app Application.yaml/values.yaml)
    Task 6 (docker push)
                ↘             ↙
              Task 9 ← MERGE POINT
              (terraform apply + verify both apps routing)
                  ↓
              Task 10 (podinfo)
                  ↓
              Task 11 (Makefile)
                  ↓
              Task 12 (CI lint job)
                  ↓
              Task 13 (CI deploy job)
                  ↓
              Task 14 (README)

  Session A is purely app code — no Kubernetes or Terraform involved. Just Python + Docker.

  Session B is purely infrastructure — the Helm chart and the Terraform ArgoCD wiring. No running cluster needed to write and lint it.

  Everything from Task 9 onward is sequential since each depends on all previous work being live in the cluster.