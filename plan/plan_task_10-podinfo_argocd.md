Plan: Task 10 — podinfo as ArgoCD app (reusing the shared chart)

  Problem to fix first: The current infra/podinfo.tf needs to be destroyed and deleted.

  Then — the right approach (2 files, ~20 lines):

  1. Check/update gitops/chart/values.yaml — add service.port as a configurable value (currently likely hardcoded to 8080;
  podinfo runs on 9898)
  2. Update gitops/chart/templates/service.yaml and deployment.yaml — make port reference {{ .Values.service.port }} instead of
   hardcoded value
  3. Create gitops/apps/podinfo/Application.yaml — ArgoCD Application pointing to gitops/chart/ just like python-app and
  echo-app
  4. Create gitops/apps/podinfo/values.yaml — sets image.repository: ghcr.io/stefanprodan/podinfo, service.port: 9898,
  path.prefix: /podinfo, replicaCount: 1
  5. Push to GitHub — ArgoCD root app auto-discovers the new Application.yaml and syncs podinfo
  6. Verify — curl localhost/podinfo returns a response

  Also: update CLAUDE.md to reflect this design decision (ArgoCD for all apps including podinfo).