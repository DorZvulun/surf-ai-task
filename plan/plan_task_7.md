# Plan: Task 7 — `gitops/chart/` Helm Chart

## Context

Phase 3 of the project replaces the old `modules/web-app/` Terraform module with a shared
Helm chart that ArgoCD will render for every app. Task 7 creates that chart from scratch.
No files exist in `gitops/` yet; `infra/` only has `main.tf` and `cluster.tf`.

Success criteria: `helm lint gitops/chart/` passes and `helm template` renders valid YAML.

---

## Files to Create

### `gitops/chart/Chart.yaml`
```yaml
apiVersion: v2
name: web-app
description: Shared Helm chart for web applications
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### `gitops/chart/values.yaml`
Defaults per CLAUDE.md spec:
```yaml
replicaCount: 2

image:
  repository: ""
  tag: "latest"
  pullPolicy: Always

path:
  prefix: "/"

namespace: default
```

### `gitops/chart/templates/deployment.yaml`
- `Deployment` with `replicas: {{ .Values.replicaCount }}`
- Image: `{{ .Values.image.repository }}:{{ .Values.image.tag }}`
- `imagePullPolicy: {{ .Values.image.pullPolicy }}`
- Container port 8080
- Downward API env vars (exact pattern from CLAUDE.md):
  ```yaml
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
  ```
- Resource naming: `{{ .Release.Name }}`

### `gitops/chart/templates/service.yaml`
- `Service` type `ClusterIP`
- Port 80 → targetPort 8080
- Name: `{{ .Release.Name }}-svc`
- Selector matches deployment labels

### `gitops/chart/templates/ingressroute.yaml`
Two CRDs, both `traefik.io/v1alpha1`:
1. **Middleware** (`stripPrefix`) — name: `{{ .Release.Name }}-strip`
   - `spec.stripPrefix.prefixes: ["{{ .Values.path.prefix }}"]`
2. **IngressRoute** — name: `{{ .Release.Name }}-route`
   - entryPoints: `[web]`
   - routes match `PathPrefix('{{ .Values.path.prefix }}')`
   - middlewares: `[{ name: {{ .Release.Name }}-strip }]`
   - service: `{{ .Release.Name }}-svc:80`

---

## Resource Naming Convention
All resources: `{{ .Release.Name }}-<type>` (e.g. `python-app-svc`, `python-app-route`)
Labels: `app.kubernetes.io/name: {{ .Release.Name }}`

---

## Verification
```bash
helm lint gitops/chart/
helm template python-app gitops/chart/ \
  --set image.repository=myuser/ironman-web-app \
  --set path.prefix=/python-app
# Inspect output: Deployment, Service, Middleware, IngressRoute all present
```
