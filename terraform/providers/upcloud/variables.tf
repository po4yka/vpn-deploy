variable "server_name" {
  type        = string
  description = "Hostname / Terraform name of the VPS."
}

variable "zone" {
  type        = string
  description = "UpCloud zone, e.g. fi-hel1, de-fra1, us-nyc1."
}

variable "plan" {
  type        = string
  description = "UpCloud plan slug, e.g. 1xCPU-2GB or DEV-2xCPU-4GB."
}

variable "storage_template" {
  type        = string
  description = "Storage template UUID to clone from. Pin to a specific Debian 13 / Ubuntu 24.04 template."
}

variable "storage_size_gb" {
  type        = number
  default     = 25
  description = "Root disk size in GB."
}

variable "admin_user" {
  type    = string
  default = "deploy"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "Public SSH key only. The matching private key stays outside this repo."
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "Source CIDRs allowed to reach 22/tcp."
}

variable "enable_hysteria" {
  type    = bool
  default = true
}

variable "nginx_xhttp_public_port" {
  type        = number
  default     = 8443
  description = "Public TCP port for nginx-xhttp. Keep this in sync with Ansible nginx_xhttp_public_port."

  validation {
    condition     = var.nginx_xhttp_public_port >= 1 && var.nginx_xhttp_public_port <= 65535
    error_message = "nginx_xhttp_public_port must be a valid TCP port."
  }
}

variable "build_env" {
  type        = string
  default     = "prod"
  description = "Free-form label baked into /etc/vpn-build-id by cloud-init."
}

variable "labels" {
  type    = map(string)
  default = {}
}
