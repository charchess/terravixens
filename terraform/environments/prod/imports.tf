# The OpenBao bootstrap resources predate Terraform ownership. Import blocks
# make that adoption visible in the plan; Terraform does not create replacements.
import {
  to = module.environment.module.argocd.kubernetes_namespace.external_secrets
  id = "external-secrets"
}

import {
  to = module.environment.module.argocd.kubernetes_secret_v1.openbao_token
  id = "external-secrets/openbao-token"
}