# TerraVixens — contrat de bootstrap, idempotence et cycle de vie

## Objet

Ce document définit le comportement attendu de TerraVixens depuis des nœuds Talos vierges en mode maintenance jusqu’à un cluster Kubernetes opéré par Argo CD, External Secrets et OpenBao. Il distingue explicitement les opérations déclaratives idempotentes des opérations destructives qui nécessitent une approbation humaine.

## Invariants de sécurité

1. Un `terraform plan -refresh=true` et un `terraform apply` exécutés sur une production stable ne doivent produire aucun changement.
2. Une modification non destructive ne doit jamais déclencher un reset Talos, un ré-bootstrap etcd, une régénération des secrets du cluster ou un effacement de nœud.
3. Une évolution control-plane est sérielle : un nœud à la fois, avec validation de l’API, des nœuds Kubernetes et d’etcd entre deux nœuds.
4. Le token OpenBao de bootstrap n’est ni commité ni un token root. Il doit être un token de service à privilèges minimaux destiné à External Secrets.
5. Un reset, une réinstallation, une suppression de membre etcd ou une réutilisation d’identité ne sont jamais une conséquence implicite d’un `terraform apply` ou `terraform destroy` ordinaire.

## Bootstrap zéro intervention manuelle

### Prérequis

Les machines Talos doivent être accessibles en mode maintenance sur leurs identités réseau déclarées. Le runner Terraform doit détenir les entrées privées hors Git :

- `terraform.tfvars`, permissions restrictives ;
- les credentials du backend state ;
- `.secrets/prod/openbao-token.yaml`, permissions `0600` ;
- un `stringData.token` OpenBao non vide dans ce fichier.

Le token de bootstrap doit disposer uniquement des lectures nécessaires au contrôleur External Secrets, par exemple la politique `vixens-eso-read`. Un token root ou administratif ne doit jamais être placé dans Kubernetes, dans `.secrets` ou dans le state Terraform.

### Séquence

```text
Talos maintenance
  -> terraform apply
  -> MachineConfigs Talos / API Kubernetes
  -> Cilium et prérequis cluster
  -> bootstrap Argo CD
  -> Secret external-secrets/openbao-token créé par Terraform
  -> Argo CD synchronise Vixens
  -> External Secrets lit OpenBao
  -> secrets applicatifs et workloads GitOps convergent
```

Aucune commande `kubectl` manuelle n’est requise dans cette séquence.

### Contrat OpenBao

Terraform utilise `var.paths.openbao_bootstrap_token`, dont le défaut production est :

```text
../../../.secrets/prod/openbao-token.yaml
```

Le module ArgoCD vérifie, avant toute création du Secret Kubernetes :

- l’existence du fichier ;
- sa capacité à être décodé comme YAML ;
- la présence de `stringData.token` ;
- que le token n’est pas vide après trim.

Un prérequis manquant ou invalide fait échouer Terraform explicitement. Aucun fallback Infisical, token hardcodé ou appel manuel `kubectl` n’est accepté.

Le Secret `external-secrets/openbao-token` est déclaré avec `wait_for_service_account_token = false`, puis adopté par les blocs `import` production s’il préexistait.

### Secret dans le state

Le fichier `.secrets` protège contre Git : il ne remplace pas le backend state. Une ressource Terraform déclarative `kubernetes_secret_v1` conserve nécessairement la valeur sensible dans le state pour pouvoir comparer et réconcilier l’objet Kubernetes.

Le state est donc une zone sensible : backend privé, contrôle d’accès minimal, transport protégé, rétention/versioning maîtrisés et procédures de rotation documentées. Les sorties Terraform restent redacted ; aucune valeur de token ne doit être imprimée dans les logs, rapports ou PR.

## Handoff bootstrap -> GitOps

Terraform possède la création initiale des prérequis de bootstrap. Après la prise de relais, Argo CD/GitOps possède les manifests runtime et les seeds ArgoCD.

En production :

```hcl
argocd_bootstrap_seed_enabled = false
```

Les ressources seed sont alors désactivées dans la configuration et leur état Terraform a été retiré après sauvegarde et vérification des objets GitOps live. Cette règle ne s’applique pas à Cilium, Talos ou aux objets que Terraform doit continuer à réconcilier fonctionnellement.

## Idempotence production

La preuve attendue est systématiquement :

```bash
terraform plan -refresh=true -input=false -lock=true -lock-timeout=2m \
  -detailed-exitcode -var-file=terraform.tfvars
# sortie attendue: 0 et "No changes."

terraform apply -input=false -lock=true -lock-timeout=2m \
  -var-file=terraform.tfvars
# sortie attendue: 0 ajouté, 0 modifié, 0 détruit
```

Ne jamais substituer `-refresh=false`, un message shell synthétique ou un plan généré sans relecture live.

## Évolution du cluster

### MachineConfig et Talos

Les endpoints de `talos_machine_configuration_apply` utilisent l’identité management déclarée (`ip_address`). Les identités bootstrap/VLAN et les endpoints historiques ne doivent pas être réutilisés aveuglément.

Avant un apply control-plane :

1. produire un plan sauvegardé ;
2. lire son JSON et vérifier exhaustivement les adresses/actions ;
3. autoriser un seul `talos_machine_configuration_apply` correspondant au nœud visé ;
4. vérifier que node/endpoint correspondent à l’identité management live ;
5. appliquer ce plan seul ;
6. vérifier `/readyz`, tous les nœuds `Ready`, le quorum et la MachineConfig effective ;
7. seulement alors poursuivre avec le nœud suivant.

`talos_rollout_enabled` reste désactivé hors fenêtre de maintenance. Une évolution d’image Talos utilise le rollout sériel avec préflight de tous les pairs, attente etcd/Kubernetes et reprise idempotente.

### Ajout, remplacement et retrait

- Ajouter un worker ou un control-plane est une opération déclarative, mais un control-plane doit préserver le quorum etcd.
- Remplacer un control-plane suit la règle **replacement first** : joindre et valider le nouveau nœud avant toute suppression de voter.
- Retirer un membre etcd, réutiliser une identité, reset ou réinstaller un nœud exigent une approbation séparée et un runbook de récupération.

## Reset et décommissionnement

Les ressources legacy de reset peuvent rester dans le state pour compatibilité, mais elles ne possèdent plus de provisioner de destruction. Le code ne doit contenir ni `when = destroy` ni appel `talos-reset.sh` pour un changement courant.

Un décommissionnement complet est une procédure distincte et explicitement approuvée : sauvegardes, inventaire, plan d’arrêt des workloads/stateful data, confirmation de perte de données, reset ciblé des seules machines concernées, puis retrait state. Il ne fait pas partie du chemin nominal `terraform destroy`.

## Validation actuelle

Les contrats automatisés couvrent :

- bootstrap OpenBao, fichier hors Git et fail-fast ;
- compatibilité avec les tfvars ignorés existants ;
- handoff des seeds ArgoCD à GitOps ;
- version Cilium déclarée égale au runtime observé ;
- endpoints Talos de gestion et stabilité des adresses legacy ;
- rollout Talos sériel : ordre, préflight, santé, quorum, reprise et noms dupliqués ;
- absence de reset destructif dans le module Talos.

La production a aussi été validée par un `plan -refresh=true` normal sans changement, suivi d’un `apply` normal à zéro ressource modifiée.

## Validation à exécuter dans un lab vierge

Le bootstrap complet depuis machines Talos maintenance doit être exécuté dans un environnement Hyper-V jetable avant de déclarer le parcours neuf certifié end-to-end. La liste exhaustive et les critères d’acceptation sont suivis dans l’issue [#9](https://github.com/charchess/terravixens/issues/9).
