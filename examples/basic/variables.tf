variable "proxmox_endpoint" {
  description = "Base URL of the Proxmox VE API, including the scheme and port."
  type        = string
  default     = "https://192.168.1.10:8006/"
}

variable "proxmox_api_token" {
  description = "API token in `user@realm!token-id=secret` form. Supply it via TF_VAR_proxmox_api_token or a tfvars file that is not committed."
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Name of the Proxmox node to create the VM on, as shown in the node list."
  type        = string
  default     = "pve"
}

variable "ssh_public_key" {
  description = "Public key line installed for the admin account, e.g. the contents of ~/.ssh/id_ed25519.pub. Supply it with `export TF_VAR_ssh_public_key=\"$(cat ~/.ssh/id_ed25519.pub)\"`."
  type        = string

  # Deliberately a key, not a path to one: `file()` is evaluated while the
  # configuration graph is built, so a default path would make `validate` and
  # `tflint` fail on any machine that does not happen to have a key there.
  validation {
    condition     = can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521))\\s+\\S+", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a full public key line such as \"ssh-ed25519 AAAA... comment\", not a path to one."
  }
}
