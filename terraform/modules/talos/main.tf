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
      echo "{\"ip\": \"$VLAN_IP\"}"
    else
      echo "{\"ip\": \"$MAINTENANCE_IP\"}"
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
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = var.worker_nodes
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = data.external.node_endpoint[each.key].result.ip
  endpoint                    = data.external.node_endpoint[each.key].result.ip
}

# SOTA: Automatic CSR Approval Task during bootstrap/join
resource "null_resource" "auto_approve_csr" {
  depends_on = [talos_cluster_kubeconfig.this]
  triggers = {
    # Re-run if nodes change
    cluster_nodes = join(",", keys(merge(var.control_plane_nodes, var.worker_nodes)))
  }

  provisioner "local-exec" {
    # Run in background to not block Terraform wait sequences
    command = "bash ../../../scripts/approve-csr.sh ../../../terraform/environments/dev/kubeconfig-dev &"
  }
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  endpoint             = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  depends_on           = [talos_machine_configuration_apply.control_plane]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  endpoint             = local.control_plane_vlan111_ips[keys(var.control_plane_nodes)[0]]
  depends_on           = [talos_machine_bootstrap.this]
}

resource "null_resource" "node_reset_on_destroy" {
  for_each = merge(var.control_plane_nodes, var.worker_nodes)
  triggers = {
    node_ip = lookup(merge(local.control_plane_vlan111_ips, local.worker_vlan111_ips), each.key, "")
  }
  provisioner "local-exec" {
    when    = destroy
    command = "bash ../../../scripts/talos-reset.sh ${self.triggers.node_ip}"
  }
}

# Sequential upgrades remain unchanged as they are already robustly sequenced
locals {
  cp_node_names_list = sort(keys(var.control_plane_nodes))
}

resource "null_resource" "control_plane_upgrade" {
  for_each = var.control_plane_nodes
  triggers = {
    talos_version     = var.talos_version
    talos_image       = var.talos_image
    node_ip           = local.control_plane_vlan111_ips[each.key]
    wait_for_previous = index(local.cp_node_names_list, each.key) > 0 ? local.cp_node_names_list[index(local.cp_node_names_list, each.key) - 1] : "none"
  }
  depends_on = [talos_machine_bootstrap.this, talos_machine_configuration_apply.control_plane]
  provisioner "local-exec" {
    command = <<-EOT
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${data.talos_client_configuration.this.talos_config}
EOF
      export TALOSCONFIG=$TEMP_TALOSCONFIG
      IMAGE="${var.talos_image != "" ? var.talos_image : format("ghcr.io/siderolabs/installer:%s", var.talos_version)}"
      PREVIOUS_IP="${lookup(local.control_plane_vlan111_ips, self.triggers.wait_for_previous, "")}"
      if [ "${self.triggers.wait_for_previous}" != "none" ]; then
        until timeout 2 bash -c "echo > /dev/tcp/$PREVIOUS_IP/50000" 2>/dev/null; do sleep 10; done
        sleep 30
      fi
      talosctl upgrade --nodes ${self.triggers.node_ip} --endpoints ${self.triggers.node_ip} --image "$IMAGE" --preserve=true --wait=true
      until timeout 2 bash -c "echo > /dev/tcp/${self.triggers.node_ip}/50000" 2>/dev/null; do sleep 10; done
      rm -f $TEMP_TALOSCONFIG
    EOT
  }
}

resource "null_resource" "worker_upgrade" {
  for_each = var.worker_nodes
  triggers = {
    talos_version = var.talos_version
    talos_image   = var.talos_image
    node_ip       = local.worker_vlan111_ips[each.key]
  }
  depends_on = [talos_machine_configuration_apply.worker]
  provisioner "local-exec" {
    command = <<-EOT
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${data.talos_client_configuration.this.talos_config}
EOF
      export TALOSCONFIG=$TEMP_TALOSCONFIG
      IMAGE="${var.talos_image != "" ? var.talos_image : format("ghcr.io/siderolabs/installer:%s", var.talos_version)}"
      talosctl upgrade --nodes ${self.triggers.node_ip} --endpoints ${self.triggers.node_ip} --image "$IMAGE" --preserve=true --wait=false
      rm -f $TEMP_TALOSCONFIG
    EOT
  }
}