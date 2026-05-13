locals {
  public_source_ips = ["0.0.0.0/0", "::/0"]
}

resource "hcloud_firewall" "vpn" {
  name   = "${var.server_name}-vpn"
  labels = local.base_labels

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = local.public_source_ips
    description = "ICMP"
  }

  dynamic "rule" {
    for_each = var.allowed_ssh_cidrs
    content {
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = [rule.value]
      description = "SSH allow ${rule.value}"
    }
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = local.public_source_ips
    description = "TCP/443 VLESS+REALITY"
  }

  dynamic "rule" {
    for_each = var.nginx_xhttp_public_port == 443 ? [] : [var.nginx_xhttp_public_port]
    content {
      direction   = "in"
      protocol    = "tcp"
      port        = tostring(rule.value)
      source_ips  = local.public_source_ips
      description = "TCP/${rule.value} nginx-xhttp"
    }
  }

  dynamic "rule" {
    for_each = var.enable_hysteria ? [443] : []
    content {
      direction   = "in"
      protocol    = "udp"
      port        = tostring(rule.value)
      source_ips  = local.public_source_ips
      description = "UDP/${rule.value} Hysteria2"
    }
  }
}

resource "hcloud_firewall_attachment" "vpn" {
  firewall_id = hcloud_firewall.vpn.id
  server_ids  = [hcloud_server.vpn.id]
}
