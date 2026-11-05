# App-of-Apps Root Application
# This Application manages all other Applications in the cluster.
# Rendered only by Terraform.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vixens-app-of-apps
  namespace: argocd
  labels:
    vixens.lab/environment: ${environment}
    vixens.lab/managed-by: terraform
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${repo_url}
    targetRevision: ${target_revision}
    path: ${overlay_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: ${self_heal}
