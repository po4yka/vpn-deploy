package terraform.policy.admin_port

# no_admin_port_exposed_to_world
#
# Deny any firewall rule that allows TCP/22, TCP/3389, or var.panel_port
# from 0.0.0.0/0 or ::/0.  SSH must be restricted to var.allowed_ssh_cidrs.
#
# Provider-specific attribute mappings:
#
#   upcloud_firewall_rules — nested firewall_rule blocks:
#     protocol, destination_port_start, source_address_start/end, action
#
#   hcloud_firewall — nested rule blocks:
#     protocol, port, source_ips, direction
#
#   vultr_firewall_rule — top-level resource:
#     protocol, port, subnet/subnet_size (0 = any)

admin_ports := {"22", "3389"}

world_cidrs := {"0.0.0.0/0", "::/0"}

panel_port := input.variables.panel_port.value

# Helper: is this a "world" source for upcloud (address range covers all IPs)?
upcloud_is_world(rule) {
  rule.source_address_start == "0.0.0.0"
  rule.source_address_end == "255.255.255.255"
}

upcloud_is_world(rule) {
  rule.source_address_start == "::"
  rule.source_address_end == "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
}

# upcloud_firewall_rules — deny world-open TCP/22 or TCP/3389
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "upcloud_firewall_rules"
  rule := rc.change.after.firewall_rule[_]
  rule.action == "accept"
  rule.direction == "in"
  rule.protocol == "tcp"
  upcloud_is_world(rule)
  admin_ports[rule.destination_port_start]

  msg := sprintf(
    "resource %q: firewall rule allows TCP/%s from world; SSH must be restricted to allowed_ssh_cidrs",
    [rc.address, rule.destination_port_start],
  )
}

# upcloud_firewall_rules — deny world-open panel_port if defined
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "upcloud_firewall_rules"
  rule := rc.change.after.firewall_rule[_]
  rule.action == "accept"
  rule.direction == "in"
  rule.protocol == "tcp"
  upcloud_is_world(rule)
  rule.destination_port_start == sprintf("%v", [panel_port])

  msg := sprintf(
    "resource %q: firewall rule allows panel_port (%v) from world",
    [rc.address, panel_port],
  )
}

# hcloud_firewall — deny world-open TCP/22 or TCP/3389
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "hcloud_firewall"
  rule := rc.change.after.rule[_]
  rule.direction == "in"
  rule.protocol == "tcp"
  world_cidrs[rule.source_ips[_]]
  admin_ports[rule.port]

  msg := sprintf(
    "resource %q: hcloud firewall rule allows TCP/%s from world; SSH must be restricted to allowed_ssh_cidrs",
    [rc.address, rule.port],
  )
}

# hcloud_firewall — deny world-open panel_port if defined
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "hcloud_firewall"
  rule := rc.change.after.rule[_]
  rule.direction == "in"
  rule.protocol == "tcp"
  world_cidrs[rule.source_ips[_]]
  rule.port == sprintf("%v", [panel_port])

  msg := sprintf(
    "resource %q: hcloud firewall rule allows panel_port (%v) from world",
    [rc.address, panel_port],
  )
}

# vultr_firewall_rule — subnet_size=0 means any source
vultr_is_world(rc) {
  rc.change.after.subnet_size == 0
}

# vultr_firewall_rule — deny world-open TCP/22 or TCP/3389
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "vultr_firewall_rule"
  rc.change.after.protocol == "tcp"
  vultr_is_world(rc)
  admin_ports[rc.change.after.port]

  msg := sprintf(
    "resource %q: vultr firewall rule allows TCP/%s from world; SSH must be restricted to allowed_ssh_cidrs",
    [rc.address, rc.change.after.port],
  )
}

# vultr_firewall_rule — deny world-open panel_port if defined
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "vultr_firewall_rule"
  rc.change.after.protocol == "tcp"
  vultr_is_world(rc)
  rc.change.after.port == sprintf("%v", [panel_port])

  msg := sprintf(
    "resource %q: vultr firewall rule allows panel_port (%v) from world",
    [rc.address, panel_port],
  )
}
