# 📋 Inventaire Matériel & Réseau (VIXENS-DEV)

Ce document sert de source de vérité pour le code Terraform afin d'éviter les erreurs de configuration lors des tests de cycle de vie.

## 🏗️ Nœuds Control Plane (VLAN 111 / 208)

| Nom | MAC Address | IP Maintenance | IP Prod (111) | IP Service (208) | Interface |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Daphne** | `00:15:5D:00:CB:10` | `192.168.0.162` | `192.168.111.162` | `192.168.208.162` | `enx00155d00cb10` |
| **Diva** | `00:15:5D:00:CB:11` | `192.168.0.164` | `192.168.111.164` | `192.168.208.164` | `enx00155d00cb11` |
| **Dulce** | `00:15:5D:00:CB:0B` | `192.168.0.163` | `192.168.111.163` | `192.168.208.163` | `enx00155d00cb0b` |

## 🌼 Nœuds Worker

| Nom | MAC Address | IP Maintenance | IP Prod (111) | IP Service (208) | Interface |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Daisy** | `00:15:5D:00:CB:21` | `192.168.0.106` | `192.168.111.165` | `192.168.208.165` | `enx00155d00cb21` |

## 🌐 Paramètres Réseau Globaux
*   **VIP Cluster (API) :** `192.168.111.160`
*   **Gateway Service :** `192.168.208.1`
*   **ArgoCD URL :** `http://192.168.208.71`
*   **DNS :** `192.168.208.70`, `192.168.208.1`
