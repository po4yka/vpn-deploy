resource "upcloud_firewall_rules" "vpn" {
  server_id = upcloud_server.vpn.id

  # Loopback / established
  firewall_rule {
    action    = "accept"
    direction = "in"
    family    = "IPv4"
    icmp_type = ""
    protocol  = "icmp"
    comment   = "ICMPv4"
  }

  firewall_rule {
    action    = "accept"
    direction = "in"
    family    = "IPv6"
    protocol  = "icmpv6"
    comment   = "ICMPv6"
  }

  # SSH from allowed CIDRs only
  dynamic "firewall_rule" {
    for_each = var.allowed_ssh_cidrs
    content {
      action                 = "accept"
      direction              = "in"
      family                 = strcontains(firewall_rule.value, ":") ? "IPv6" : "IPv4"
      protocol               = "tcp"
      destination_port_start = "22"
      destination_port_end   = "22"
      source_address_start   = split("/", firewall_rule.value)[0]
      source_address_end     = split("/", firewall_rule.value)[0]
      comment                = "SSH allow ${firewall_rule.value}"
    }
  }

  # Primary REALITY / nginx-xhttp
  firewall_rule {
    action                 = "accept"
    direction              = "in"
    family                 = "IPv4"
    protocol               = "tcp"
    destination_port_start = "443"
    destination_port_end   = "443"
    comment                = "TCP/443 VLESS+REALITY / nginx-xhttp"
  }

  firewall_rule {
    action                 = "accept"
    direction              = "in"
    family                 = "IPv6"
    protocol               = "tcp"
    destination_port_start = "443"
    destination_port_end   = "443"
    comment                = "TCP/443 IPv6"
  }

  # Hysteria2 — UDP/443, conditional
  dynamic "firewall_rule" {
    for_each = var.enable_hysteria ? ["v4", "v6"] : []
    content {
      action                 = "accept"
      direction              = "in"
      family                 = firewall_rule.value == "v4" ? "IPv4" : "IPv6"
      protocol               = "udp"
      destination_port_start = "443"
      destination_port_end   = "443"
      comment                = "UDP/443 Hysteria2"
    }
  }

  # Default deny inbound
  firewall_rule {
    action    = "drop"
    direction = "in"
    family    = "IPv4"
    comment   = "default deny inbound"
  }

  firewall_rule {
    action    = "drop"
    direction = "in"
    family    = "IPv6"
    comment   = "default deny inbound v6"
  }
}
