provider "upcloud" {
  # Credentials come from environment variables — never put them in tfvars or state.
  #   UPCLOUD_USERNAME  (or UPCLOUD_API_USERNAME)
  #   UPCLOUD_PASSWORD  (or UPCLOUD_API_PASSWORD)
  # Use a dedicated sub-account with only the rights this stack needs.
}
