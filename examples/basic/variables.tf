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

variable "ssh_public_key_path" {
  description = "Path to the public key installed for the admin account. The key material is read here, in the root module, so the child module never touches the filesystem."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
