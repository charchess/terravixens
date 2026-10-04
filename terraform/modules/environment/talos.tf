# ============================================================================
# TALOS CLUSTER CONFIGURATION
# ============================================================================

module "talos_cluster" {
  source = "../talos"

  cluster_name        = var.cluster.name
  talos_version       = var.cluster.talos_version
  talos_image         = var.cluster.talos_image
  kubernetes_version  = var.cluster.kubernetes_version
  cluster_endpoint    = var.cluster.endpoint
  cluster_vip         = var.cluster.vip
  control_plane_nodes = var.control_plane_nodes
  worker_nodes        = var.worker_nodes
}

# ----------------------------------------------------------------------------
# KUBECONFIG & TALOSCONFIG FILES
# ----------------------------------------------------------------------------
resource "local_file" "kubeconfig" {
  content         = module.talos_cluster.kubeconfig
  filename        = var.paths.kubeconfig
  file_permission = "0600"
}

resource "local_file" "talosconfig" {
  content         = module.talos_cluster.talosconfig
  filename        = var.paths.talosconfig
  file_permission = "0600"

  # Ensure this is written even if subsequent cluster resources fail
  lifecycle {
    ignore_changes = all
  }
}

# ----------------------------------------------------------------------------
# WAIT FOR KUBERNETES API
# ----------------------------------------------------------------------------
resource "null_resource" "wait_for_k8s_api" {
  triggers = {
    kubeconfig_id = local_file.kubeconfig.id
  }

  provisioner "local-exec" {
    command = "${local.repo_root}/scripts/wait-for-k8s-api.sh ${var.paths.kubeconfig}"
  }

  depends_on = [
    local_file.kubeconfig,
    module.talos_cluster
  ]
}

# Live version is non-sensitive observed state. Including it in triggers makes
# a manually drifted node converge on the next apply.
data "external" "talos_observed_version" {
  for_each = var.talos_rollout_enabled ? merge(
    { for name in var.control_plane_rollout_order : name => module.talos_cluster.control_plane_node_ips[name] },
    { for name in sort(keys(var.worker_nodes)) : name => module.talos_cluster.worker_node_ips[name] },
  ) : {}
  program    = ["${local.repo_root}/scripts/talos-observed-version.sh"]
  query      = { ip = each.value, talosconfig = local_file.talosconfig.filename }
  depends_on = [local_file.talosconfig]
}

# Credentials are written before rollout. Only their protected paths are passed to the script.
resource "terraform_data" "talos_rollout" {
  count = var.talos_rollout_enabled ? 1 : 0

  input = {
    talos_version     = var.cluster.talos_version
    talos_image       = var.cluster.talos_image
    control_plane     = var.control_plane_rollout_order
    workers           = sort(keys(var.worker_nodes))
    observed_versions = { for name, observed in data.external.talos_observed_version : name => observed.result.version }
  }

  triggers_replace = [
    var.cluster.talos_version,
    var.cluster.talos_image,
    jsonencode({ for name, observed in data.external.talos_observed_version : name => observed.result.version }),
    jsonencode([for name in var.control_plane_rollout_order : {
      name = name
      ip   = module.talos_cluster.control_plane_node_ips[name]
    }]),
    jsonencode([for name in sort(keys(var.worker_nodes)) : {
      name = name
      ip   = module.talos_cluster.worker_node_ips[name]
    }]),
  ]

  lifecycle {
    precondition {
      condition = (
        !var.talos_rollout_enabled || (
          length(var.control_plane_rollout_order) == length(var.control_plane_nodes) &&
          length(setsubtract(toset(var.control_plane_rollout_order), toset(keys(var.control_plane_nodes)))) == 0
        )
      )
      error_message = "control_plane_rollout_order must list every control-plane node exactly once."
    }
  }

  provisioner "local-exec" {
    command = "${local.repo_root}/scripts/talos-rollout.sh"
    environment = {
      TALOSCONFIG         = local_file.talosconfig.filename
      KUBECONFIG          = local_file.kubeconfig.filename
      TALOS_VERSION       = var.cluster.talos_version
      TALOS_IMAGE         = var.cluster.talos_image != "" ? var.cluster.talos_image : format("ghcr.io/siderolabs/installer:%s", var.cluster.talos_version)
      CONTROL_PLANE_NODES = jsonencode([for name in var.control_plane_rollout_order : { name = name, ip = module.talos_cluster.control_plane_node_ips[name] }])
      WORKER_NODES        = jsonencode([for name in sort(keys(var.worker_nodes)) : { name = name, ip = module.talos_cluster.worker_node_ips[name] }])
    }
  }

  depends_on = [
    local_file.talosconfig,
    local_file.kubeconfig,
    module.talos_cluster,
  ]
}
