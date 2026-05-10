locals {
  user_data = templatefile("${path.module}/../../shared/cloud-init.yaml.tftpl", {
    admin_user           = var.admin_user
    admin_ssh_public_key = var.admin_ssh_public_key
    build_env            = var.build_env
  })

  base_labels = merge(var.labels, {
    role        = "vpn"
    managed_by  = "terraform"
    provisioner = "ansible"
    env         = var.build_env
  })
}

resource "upcloud_server" "vpn" {
  hostname = var.server_name
  zone     = var.zone
  plan     = var.plan

  cpu = null
  mem = null

  metadata  = true
  user_data = local.user_data

  template {
    storage = var.storage_template
    size    = var.storage_size_gb
    title   = "${var.server_name}-root"

    backup_rule {
      interval  = "daily"
      time      = "0300"
      retention = 7
    }
  }

  network_interface {
    type = "public"
  }

  network_interface {
    type = "utility"
  }

  login {
    user            = var.admin_user
    keys            = [var.admin_ssh_public_key]
    create_password = false
  }

  labels = local.base_labels

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      user_data,
      template[0].title,
    ]
  }
}
