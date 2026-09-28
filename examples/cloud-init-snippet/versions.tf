terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  # An example is a root module, so this is where the provider is actually
  # configured. The module itself only declares that it needs this provider.
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.114.0"
    }
  }
}
