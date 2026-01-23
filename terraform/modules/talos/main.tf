# Talos Machine Secrets - generated once per cluster
resource "talos_machine_secrets" "cluster" {}

# Extract VIP address from cluster_endpoint
locals {
  vip_address = regex("https?://([^:]+)", var.cluster_endpoint)[0]
}

# Generate per-node configuration patches
locals {
  node_patches = {
    for k, v in var.control_plane_nodes : k => yamlencode({
      machine = {
        install = merge(
          {
            disk = v.install_disk
          },
          # Add custom image only if provided (non-empty string)
          var.talos_image != "" ? { image = var.talos_image } : {}
        )
        network = merge(
          {
            hostname = v.name # Set node hostname
            interfaces = [{
              interface = v.network.interface
              dhcp      = false # Disable DHCP on physical interface
              addresses = []    # No IP on untagged interface
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
                  # Add VIP on internal VLAN (no gateway = VLAN 111)
                  vlan.gateway == "" ? {
                    vip = {
                      ip = local.vip_address
                    }
                  } : {}
                )
              ]
            }]
          },
          # Add nameservers only if provided (non-empty list)
          length(v.nameservers) > 0 ? { nameservers = v.nameservers } : {}
        )
      }
      cluster = {
        network = {
          podSubnets     = [var.pod_subnet]
          serviceSubnets = [var.service_subnet]
          # Disable default CNI (Flannel) to use Cilium instead
          cni = {
            name = "none"
          }
        }
        # Disable kube-proxy (Cilium replaces it)
        proxy = {
          disabled = true
        }
        # Add VIP to API server certificates
        apiServer = {
          certSANs = [local.vip_address]
        }
      }
    })
  }

  # Extract VLAN IP with gateway (routable IP) for each control plane node
  # This is used for talosctl reset during destroy, as nodes are not reachable on maintenance IPs
  control_plane_vlan_ips = {
    for k, v in var.control_plane_nodes : k => [
      for vlan in v.network.vlans :
      split("/", vlan.addresses[0])[0]
      if vlan.gateway != ""
    ][0]
  }

  control_plane_vlan111_ips = {
    for k, v in var.control_plane_nodes : k => [
      for vlan in v.network.vlans :
      split("/", vlan.addresses[0])[0]
      if vlan.vlanId == 111
    ][0]
  }

  # Extract VLAN IP with gateway for each worker node
  worker_vlan_ips = {
    for k, v in var.worker_nodes : k => [
      for vlan in v.network.vlans :
      split("/", vlan.addresses[0])[0]
      if vlan.gateway != ""
    ][0]
  }
}

data "talos_machine_configuration" "control_plane" {
  for_each = var.control_plane_nodes

  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  talos_version    = var.talos_version

  config_patches = [
    local.node_patches[each.key]
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [local.vip_address] # Always use VIP for endpoint
  nodes = [
    for k, v in var.control_plane_nodes : local.control_plane_vlan111_ips[k]
  ]
}

# Control plane nodes configuration auto-detection
data "external" "control_plane_endpoint" {
  for_each = var.control_plane_nodes

  program = ["bash", "-c", <<-EOT
    VLAN_IP="${local.control_plane_vlan_ips[each.key]}"
    MAINTENANCE_IP="${each.value.ip_address}"

    # Test if node responds on VLAN IP (already configured)
    if timeout 2 bash -c "echo > /dev/tcp/$VLAN_IP/50000" 2>/dev/null; then
      echo "{\"ip\": \"$VLAN_IP\", \"status\": \"configured\"}"
    else
      echo "{\"ip\": \"$MAINTENANCE_IP\", \"status\": \"new\"}"
    fi
  EOT
  ]
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = var.control_plane_nodes

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane[each.key].machine_configuration
  # Auto-detect: use VLAN IP if node already configured, maintenance IP if new/reset
  node     = data.external.control_plane_endpoint[each.key].result.ip
  endpoint = data.external.control_plane_endpoint[each.key].result.ip
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.control_plane
  ]
  # Use the first control plane node's detected IP for bootstrap
  node                 = [for k, v in var.control_plane_nodes : data.external.control_plane_endpoint[k].result.ip][0]
  client_configuration = talos_machine_secrets.cluster.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]
  client_configuration = talos_machine_secrets.cluster.client_configuration
  # Use the first control plane node's detected IP to fetch kubeconfig
  node = [for k, v in var.control_plane_nodes : data.external.control_plane_endpoint[k].result.ip][0]
  # BUT ensure the kubeconfig file itself points to the VIP
  endpoint = local.vip_address
}

# Automatic node reset on destroy - Control Plane
resource "null_resource" "node_reset_on_destroy" {
  for_each = var.control_plane_nodes

  # This resource depends on the cluster being configured
  depends_on = [
    talos_machine_bootstrap.this
  ]

  # Store talosconfig content and VLAN IP in triggers
  # Using VLAN IP with gateway (routable IP) because nodes are not reachable on maintenance IPs after config is applied
  # This ensures the talosconfig is available even after local_file is destroyed
  triggers = {
    node_ip     = local.control_plane_vlan_ips[each.key]
    talosconfig = data.talos_client_configuration.this.talos_config
  }

  # Reset node before destroying terraform state
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Create temporary talosconfig file with stored content
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${self.triggers.talosconfig}
EOF

      export TALOSCONFIG=$TEMP_TALOSCONFIG
      echo "Resetting node ${self.triggers.node_ip} before destroy..."
      talosctl reset \
        -n ${self.triggers.node_ip} \
        -e ${self.triggers.node_ip} \
        --system-labels-to-wipe STATE \
        --system-labels-to-wipe EPHEMERAL \
        --graceful=false \
        --reboot \
        --wait=false || echo "Warning: Node reset failed, continuing destroy"

      # Cleanup temp file
      rm -f $TEMP_TALOSCONFIG
      echo "Node ${self.triggers.node_ip} reset initiated"
    EOT
  }

  lifecycle {
    ignore_changes = [triggers]
  }
}

# Worker nodes configuration

# Auto-detect if worker is already configured (reachable on VLAN IP)
# If not reachable on VLAN, use maintenance IP for initial bootstrap
data "external" "worker_endpoint" {
  for_each = var.worker_nodes

  program = ["bash", "-c", <<-EOT
    VLAN_IP="${local.worker_vlan_ips[each.key]}"
    MAINTENANCE_IP="${each.value.ip_address}"

    # Test if node responds on VLAN IP (already configured)
    if timeout 2 bash -c "echo > /dev/tcp/$VLAN_IP/50000" 2>/dev/null; then
      echo "{\"ip\": \"$VLAN_IP\", \"status\": \"configured\"}"
    else
      echo "{\"ip\": \"$MAINTENANCE_IP\", \"status\": \"new\"}"
    fi
  EOT
  ]
}

locals {
  worker_patches = {
    for k, v in var.worker_nodes : k => yamlencode({
      machine = {
        install = merge(
          {
            disk = v.install_disk
          },
          # Add custom image only if provided (non-empty string)
          var.talos_image != "" ? { image = var.talos_image } : {}
        )
        network = merge(
          {
            hostname = v.name # Set node hostname
            interfaces = [{
              interface = v.network.interface
              dhcp      = false # Disable DHCP on physical interface
              addresses = []    # No IP on untagged interface
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
          # Add nameservers only if provided (non-empty list)
          length(v.nameservers) > 0 ? { nameservers = v.nameservers } : {}
        )
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

data "talos_machine_configuration" "worker" {
  for_each = var.worker_nodes

  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  talos_version    = var.talos_version

  config_patches = [
    local.worker_patches[each.key]
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  # Auto-detect: use VLAN IP if node already configured, maintenance IP if new
  node     = data.external.worker_endpoint[each.key].result.ip
  endpoint = data.external.worker_endpoint[each.key].result.ip
}

# Automatic node reset on destroy - Workers
resource "null_resource" "worker_reset_on_destroy" {
  for_each = var.worker_nodes

  # This resource depends on the worker being configured
  depends_on = [
    talos_machine_configuration_apply.worker
  ]

  # Store talosconfig content and VLAN IP in triggers
  # Using VLAN IP with gateway (routable IP) because nodes are not reachable on maintenance IPs after config is applied
  # This ensures the talosconfig is available even after local_file is destroyed
  triggers = {
    node_ip     = local.worker_vlan_ips[each.key]
    talosconfig = data.talos_client_configuration.this.talos_config
  }

  # Reset node before destroying terraform state
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Create temporary talosconfig file with stored content
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${self.triggers.talosconfig}
EOF

      export TALOSCONFIG=$TEMP_TALOSCONFIG
      echo "Resetting worker node ${self.triggers.node_ip} before destroy..."
      talosctl reset \
        -n ${self.triggers.node_ip} \
        -e ${self.triggers.node_ip} \
        --system-labels-to-wipe STATE \
        --system-labels-to-wipe EPHEMERAL \
        --graceful=false \
        --reboot \
        --wait=false || echo "Warning: Worker node reset failed, continuing destroy"

      # Cleanup temp file
      rm -f $TEMP_TALOSCONFIG
      echo "Worker node ${self.triggers.node_ip} reset initiated"
    EOT
  }

  lifecycle {
    ignore_changes = [triggers]
  }
}

# Sequential upgrade management for Control Plane
locals {
  cp_node_names_list = sort(keys(var.control_plane_nodes))
}

# Automatic Talos upgrade when talos_version or talos_image changes - Control Plane
resource "null_resource" "control_plane_upgrade" {
  for_each = var.control_plane_nodes

  # Trigger upgrade when version or image changes
  triggers = {
    talos_version = var.talos_version
    talos_image   = var.talos_image
    node_ip       = local.control_plane_vlan_ips[each.key]
    
    # Logic to force sequential execution without cyclic dependencies
    # Each node (except the first) waits for the previous one in the sorted list
    # by depending on its apply configuration, but we manually sequence the PROVISIONER
    wait_for_previous = index(local.cp_node_names_list, each.key) > 0 ? local.cp_node_names_list[index(local.cp_node_names_list, each.key) - 1] : "none"
  }

  # Upgrade must happen after node is configured and bootstrapped
  depends_on = [
    talos_machine_bootstrap.this,
    talos_machine_configuration_apply.control_plane
  ]

  # Upgrade node when triggers change
  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary talosconfig file
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${data.talos_client_configuration.this.talos_config}
EOF

      export TALOSCONFIG=$TEMP_TALOSCONFIG

      # Determine image to use
      IMAGE="${var.talos_image != "" ? var.talos_image : format("ghcr.io/siderolabs/installer:%s", var.talos_version)}"

      # Manual sequencing for safety
      if [ "${self.triggers.wait_for_previous}" != "none" ]; then
        echo "Waiting for previous node ${self.triggers.wait_for_previous} to be Ready before upgrading ${self.triggers.node_ip}..."
        # Wait until the previous node is responding on port 50000 (Talos API)
        until timeout 2 bash -c "echo > /dev/tcp/${local.control_plane_vlan_ips[self.triggers.wait_for_previous]}/50000" 2>/dev/null; do
          sleep 10
        done
        echo "Previous node is UP. Waiting 30s for etcd stability..."
        sleep 30
      fi

      echo "Upgrading node ${self.triggers.node_ip} to $IMAGE..."
      talosctl upgrade \
        --nodes ${self.triggers.node_ip} \
        --endpoints ${self.triggers.node_ip} \
        --image "$IMAGE" \
        --preserve=true \
        --wait=true

      echo "Node ${self.triggers.node_ip} upgrade initiated. Waiting for node to come back..."
      until timeout 2 bash -c "echo > /dev/tcp/${self.triggers.node_ip}/50000" 2>/dev/null; do
        sleep 10
      done
      
      echo "Node ${self.triggers.node_ip} is back. Finalizing upgrade step."
      rm -f $TEMP_TALOSCONFIG
    EOT
  }
}

# Automatic Talos upgrade when talos_version or talos_image changes - Workers
resource "null_resource" "worker_upgrade" {
  for_each = var.worker_nodes

  # Trigger upgrade when version or image changes
  triggers = {
    talos_version = var.talos_version
    talos_image   = var.talos_image
    node_ip       = local.worker_vlan_ips[each.key]
  }

  # Upgrade must happen after node is configured
  depends_on = [
    talos_machine_configuration_apply.worker
  ]

  # Upgrade node when triggers change
  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary talosconfig file
      TEMP_TALOSCONFIG=$(mktemp)
      cat > $TEMP_TALOSCONFIG <<'EOF'
${data.talos_client_configuration.this.talos_config}
EOF

      export TALOSCONFIG=$TEMP_TALOSCONFIG

      # Determine image to use
      IMAGE="${var.talos_image != "" ? var.talos_image : format("ghcr.io/siderolabs/installer:%s", var.talos_version)}"

      echo "Upgrading worker node ${self.triggers.node_ip} to $IMAGE..."
      talosctl upgrade \
        --nodes ${self.triggers.node_ip} \
        --endpoints ${self.triggers.node_ip} \
        --image "$IMAGE" \
        --preserve=true \
        --wait=false

      # Cleanup temp file
      rm -f $TEMP_TALOSCONFIG
      echo "Worker node ${self.triggers.node_ip} upgrade initiated"
    EOT
  }
}
