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

variable "cloud_image_file_id" {
  description = "Image already present in a datastore, in Proxmox's `datastore:content_type/file_name` form. Download it once by hand, or with the basic example, and reuse it here."
  type        = string
  default     = "local:iso/debian-12-genericcloud-amd64.img"
}

variable "vm_datastore_id" {
  description = "Datastore for the boot disk and the cloud-init drive."
  type        = string
  default     = "local-lvm"
}

variable "data_datastore_id" {
  description = "Datastore for the second, larger disk — separate here to show that a data disk does not have to follow the boot disk."
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key_path" {
  description = "Path to the public key installed for the admin account. The key material is read here, in the root module, so the child module never touches the filesystem."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
