terraform {
  # Keep the floor in step with the pinned entry in the Validate workflow's
  # matrix: CI proves the constraint this module advertises is true.
  required_version = ">= 1.9.0, < 2.0.0"

  # Provider *configuration* stays in the root module; a child module only
  # declares which providers it needs so it inherits the root's instances.
  #
  # bpg/proxmox is pre-1.0 and moves its resource schema between minor
  # releases — `network_device` turned from a block into a list attribute in
  # 0.x, for one — so the constraint is held to a single minor.
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
  }
}
