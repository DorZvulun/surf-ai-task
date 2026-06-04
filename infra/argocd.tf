resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  wait       = true

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name  = "server.extraArgs[1]"
    value = "--rootpath=/argocd"
  }

  set {
    name  = "configs.cm.url"
    value = "http://localhost/argocd"
  }

  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_manifest" "argocd_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "argocd"
      namespace = "argocd"
    }
    spec = {
      entryPoints = ["web"]
      routes = [{
        match = "PathPrefix(`/argocd`)"
        kind  = "Rule"
        services = [{
          name = "argocd-server"
          port = 80
        }]
      }]
    }
  }

  depends_on = [helm_release.argocd]
}
