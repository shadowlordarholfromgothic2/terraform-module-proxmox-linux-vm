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

variable "ssh_username" {
  description = "User the provider opens the SFTP session as when it uploads the snippet. It needs write access to the datastore's snippets directory, which in practice means root or a user with sudo."
  type        = string
  default     = "root"
}

variable "snippet_datastore_id" {
  description = "Datastore the snippet is uploaded to. It has to allow the `snippets` content type — add it under Datacenter > Storage > (datastore) > Content, because Proxmox enables it nowhere by default."
  type        = string
  default     = "local"
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

variable "admin_password_hash" {
  description = "Crypt hash for the admin account's password, from `mkpasswd -m sha512crypt`. Null leaves the account key-only and locked. A hash reaches the guest unchanged through the snippet, which is not true of Proxmox's own cipassword field."
  type        = string
  default     = null
  sensitive   = true
}
