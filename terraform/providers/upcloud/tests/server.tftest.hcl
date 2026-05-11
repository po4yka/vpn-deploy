# Asserts on the server resource itself.

mock_provider "upcloud" {}

variables {
  server_name          = "vpn-test"
  zone                 = "fi-hel1"
  plan                 = "1xCPU-2GB"
  storage_template     = "01000000-0000-4000-8000-000020030200"
  admin_ssh_public_key = "ssh-ed25519 AAAATESTKEY test@harness"
  allowed_ssh_cidrs    = ["203.0.113.42/32"]
}

# Cloud-init carries the build label downward into the VM. A refactor
# that drops the `metadata = true` attribute would silently disable
# cloud-init — host comes up unconfigured, ansible runs into a stock
# image. Tested as a plan-time invariant.
run "server_metadata_is_enabled" {
  command = plan

  assert {
    condition     = upcloud_server.vpn.metadata == true
    error_message = "upcloud_server.metadata must remain true; cloud-init depends on it"
  }
}

# Honeypot toggle controls whether a second public IPv4 is allocated.
# Default-off: catches accidental cost regression.
run "server_no_secondary_public_ip_by_default" {
  command = plan

  assert {
    condition = length([
      for ni in upcloud_server.vpn.network_interface :
      ni if ni.type == "public"
    ]) == 1
    error_message = "Default deploy must allocate exactly one public NIC — secondary is opt-in"
  }
}

run "server_secondary_public_ip_when_honeypot_enabled" {
  command = plan

  variables {
    additional_public_ip = true
  }

  assert {
    condition = length([
      for ni in upcloud_server.vpn.network_interface :
      ni if ni.type == "public"
    ]) == 2
    error_message = "additional_public_ip=true must allocate the second public NIC for the honeypot role"
  }
}

# Server template must always be a UUID-shaped string. Catches the
# REPLACE_WITH_TEMPLATE_UUID placeholder leaking past PR review.
run "rejects_unfilled_template_placeholder" {
  command = plan

  variables {
    storage_template = "REPLACE_WITH_TEMPLATE_UUID"
  }

  # Module does not constrain this format today; the test documents the
  # contract operator-side. We don't expect_failures here because the
  # provider rejects it at apply time. The assertion below makes the
  # intent visible: any future variable validation should pass it.
  assert {
    condition     = can(regex("^[0-9a-f-]{8,}$", var.storage_template))
    error_message = "storage_template must be a UUID-shaped UpCloud template, not a placeholder"
  }
}
