# Backlog de Validation: Future Stress Tests

Ce document liste les scénarios de test identifiés pour durcir davantage la plateforme TerraVixens.

## 🟢 Priorité Haute (Prochaine Session)

### DR-01: Remplacement de nœud "à chaud"
*   **Scénario:** Reset manuel d'un nœud (ex: Dulce) sans toucher au state Terraform.
*   **Objectif:** Vérifier que Terraform ré-initialise le nœud et le ré-intègre au quorum etcd existant sans impact sur les autres membres.

### SEC-01: Rotation des Secrets Talos
*   **Scénario:** Générer de nouveaux secrets machine (re-run secrets resource).
*   **Objectif:** Comprendre l'impact sur un cluster existant. (Note: Risque élevé de ré-initialisation complète nécessaire).

### OPS-01: Upgrade Kubernetes
*   **Scénario:** Changer `kubernetes_version` dans le cluster object.
*   **Objectif:** Valider la capacité de Talos à orchestrer l'upgrade des composants K8s indépendamment de l'OS.

## 🟡 Priorité Moyenne (Post-Apps)

### PROM-02: Démotion (CP -> Worker)
*   **Scénario:** Tenter de repasser un CP en Worker.
*   **Objectif:** Vérifier que la validation Terraform bloque le passage à un nombre pair de CP. Valider la procédure manuelle de sortie d'etcd.

### NET-01: Failover de la VIP
*   **Scénario:** Couper le nœud porteur de la VIP.
*   **Objectif:** Mesurer le temps de bascule et la résilience du endpoint d'API.

## 🔴 Postposé (Storage & Complex Networking)

### STO-01: Résilience Synology CSI
*   **Scénario:** Upgrade d'OS pendant une écriture disque intense via PVC.
*   **Objectif:** Vérifier le Drain/Cordon correct et la migration du volume sans corruption.

### NET-02: Partitionnement Réseau (Split-Brain)
*   **Scénario:** Isoler le VLAN de management sur un nœud.
*   **Objectif:** Observer le comportement d'etcd et Cilium en cas de perte partielle de connectivité.
