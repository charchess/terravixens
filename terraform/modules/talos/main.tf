# Talos Machine Secrets - generated once per cluster
resource "talos_machine_secrets" "cluster" {}

# Extract VIP address from variables
locals {
  vip_address = var.cluster_vip
}

# Generate per-node configuration patches
locals {
  # Universal VLAN 111 Extraction
  control_plane_vlan111_ips = {
    for k, v in var.control_plane_nodes : k => try(
      [for vlan in v.network.vlans : split("/", vlan.addresses[0])[0] if vlan.vlanId == 111][0],
      v.ip_address
    )
  }

  worker_vlan111_ips = {
    for k, v in var.worker_nodes : k => try(
      [for vlan in v.network.vlans : split("/", vlan.addresses[0])[0] if vlan.vlanId == 111][0],
      v.ip_address
    )
  }

  node_patches = {
    for k, v in var.control_plane_nodes : k => yamlencode({
      machine = {
        install = merge(
          { disk = v.install_disk },
          var.talos_image != "" ? { image = var.talos_image } : {}
        )
        network = merge(
          {
            hostname = v.name
            interfaces = [{
              interface = v.network.interface
              dhcp      = false
              addresses = []
              vlans = [
                for vlan in v.network.vlans : merge(
                  {
                    vlanId    = vlan.vlanId
                    addresses = vlan.addresses
                    routes = vlan.gateway != "" ? [{
                      network = "0.0.0.0/0"
                      gateway = vlan.gateway
                    }] : []
                  },
                  vlan.gateway == "" ? { vip = { ip = local.vip_address } } : {}
                )
              ]
            }]
          },
          length(v.nameservers) > 0 ? { nameservers = v.nameservers } : {}
        )
        kubelet = {
          extraArgs = { "node-ip" = local.control_plane_vlan111_ips[k] }
        }
      }
      cluster = {
        network = {
          podSubnets     = [var.pod_subnet]
          serviceSubnets = [var.service_subnet]
          cni            = { name = "none" }
        }
        proxy     = { disabled = true }
        apiServer = { certSANs = [local.vip_address] }
      }
    })
  }

  worker_patches = {
    for k, v in var.worker_nodes : k => yamlencode({
      machine = {
        install = merge(
          { disk = v.install_disk },
          var.talos_image != "" ? { image = var.talos_image } : {}
        )
        network = merge(
          {
            hostname = v.name
            interfaces = [{
              interface = v.network.interface
              dhcp      = false
              addresses = []
              vlans = [
                for vlan in v.network.vlans : {
                  vlanId    = vlan.vlanId
                  addresses = vlan.addresses
                  routes = vlan.gateway != "" ? [{
                    network = "0.0.0.0/0"
                    gateway = vlan.gateway
                  }] : []
                }
              ]
            }]
          },
          length(v.nameservers) > 0 ? { nameservers = v.nameservers } : {}
        )
        kubelet = {
          extraArgs = { "node-ip" = local.worker_vlan111_ips[k] }
        }
      }
      cluster = {
        network = {
          podSubnets     = [var.pod_subnet]
          serviceSubnets = [var.service_subnet]
        }
      }
    })
  }
}

data "talos_machine_configuration" "control_plane" {
  for_each         = var.control_plane_nodes
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  talos_version    = var.talos_version
  config_patches   = [local.node_patches[each.key]]
}

data "talos_machine_configuration" "worker" {
  for_each         = var.worker_nodes
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  talos_version    = var.talos_version
  config_patches   = [local.worker_patches[each.key]]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [local.vip_address]
  nodes                = [for k, v in var.control_plane_nodes : local.control_plane_vlan111_ips[k]]
}

# Unified Auto-Detection for Apply
data "external" "node_endpoint" {
  for_each = merge(var.control_plane_nodes, var.worker_nodes)
  program = ["bash", "-c", <<-EOT
    VLAN_IP="${lookup(merge(local.control_plane_vlan111_ips, local.worker_vlan111_ips), each.key, "")}"
    MAINTENANCE_IP="${each.value.ip_address}"
    if timeout 2 bash -c "echo > /dev/tcp/$VLAN_IP/50000" 2>/dev/null; then
      # Installed nodes stage MachineConfig; maintenance stays with the health-gated rollout.
      echo "{\"ip\": \"$VLAN_IP\", \"existing\": \"true\"}"
    else
      # Fresh maintenance/DHCP nodes retain their bootstrap behavior.
      echo "{\"ip\": \"$MAINTENANCE_IP\", \"existing\": \"false\"}"
    fi
  EOT
  ]
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each                    = var.control_plane_nodes
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane[each.key].machine_configuration
  node                        = data.external.node_endpoint[each.key].result.ip
  endpoint                    = data.external.node_endpoint[each.key].result.ip
  apply_mode                  = data.external.node_endpoint[each.key].result.existing == "true" ? "staged_if_needing_reboot" : "auto"

  on_destroy = {
    graceful = true
    reboot   = false
    reset    = false
  }
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = var.worker_nodes
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = data.external.node_endpoint[each.key].result.ip
  endpoint                    = data.external.node_endpoint[each.key].result.ip
  apply_mode                  = data.external.node_endpoint[each.key].result.existing == "true" ? "staged_if_needing_reboot" : "auto"

  on_destroy = {
    graceful = true
    reboot   = false
    reset    = false
  }
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  endpoint             = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  depends_on           = [talos_machine_configuration_apply.control_plane]

  lifecycle {
    ignore_changes = [node, endpoint]
  }
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  endpoint             = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  depends_on           = [talos_machine_bootstrap.this]

  lifecycle {
    ignore_changes = [node, endpoint]
  }
}

# Keeps legacy state addresses stable while the old destructive destroy hook is
# retired. Intentionally no provisioner and no on_destroy action: removing this
# resource later is a state-only operation after an explicitly approved apply.
resource "null_resource" "node_reset_on_destroy" {
  for_each = merge(var.control_plane_nodes, var.worker_nodes)

  triggers = {
    node_ip     = lookup(merge(local.control_plane_vlan111_ips, local.worker_vlan111_ips), each.key, "")
    talosconfig = data.talos_client_configuration.this.talos_config
  }
}
