package terraform.policy.no_secrets_in_user_data

# cloud_init_user_data_contains_no_secrets
#
# Deny if any server resource's user_data (cloud-init) contains a plaintext
# secret-like pattern: a key/value pair matching
#   (secret|password|token|key)\s*[:=]\s*[^\s]{6,}
#
# Placeholder substitutions (e.g. "{{ admin_user }}") produced by Terraform's
# templatefile() are acceptable; only literal non-whitespace values of 6+
# characters trigger the rule.
#
# Applies to: upcloud_server, hcloud_server, vultr_instance

server_resource_types := {
  "upcloud_server",
  "hcloud_server",
  "vultr_instance",
}

# Regex matches literal secret assignments in plaintext.
# Pattern: secret/password/token/key followed by : or = and 6+ non-space chars.
secret_pattern := `(?i)(secret|password|token|key)\s*[:=]\s*[^\s]{6,}`

deny[msg] {
  rc := input.resource_changes[_]
  server_resource_types[rc.type]
  user_data := rc.change.after.user_data

  # user_data present and non-null
  user_data != null
  user_data != ""

  regex.match(secret_pattern, user_data)

  msg := sprintf(
    "resource %q (%s): user_data appears to contain a plaintext secret (matched pattern %q); use templatefile() placeholders or SOPS-encrypted values passed via Ansible",
    [rc.address, rc.type, secret_pattern],
  )
}
