provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # A stock Proxmox node serves the API with a self-signed certificate. Drop
  # this once the node presents one the machine running OpenTofu trusts.
  insecure = true
}

module "vm" {
  source = "../.."

  name      = "db-01"
  node_name = var.proxmox_node

  # A fixed ID keeps the machine recognisable across rebuilds — in backups, in
  # the task log, and in anything outside Terraform that refers to it.
  vm_id = 9001
  tags  = ["debian", "database", "example"]

  description = "Managed by OpenTofu — see terraform-module-proxmox-linux-vm"

  # Already in a datastore, so nothing is downloaded. Changing this replaces
  # the VM: under the `iso` content type the image reaches the disk through an
  # attribute the provider marks as forcing replacement.
  cloud_image = { file_id = var.cloud_image_file_id }

  cpu_cores    = 4
  memory_mb    = 8192
  datastore_id = var.vm_datastore_id
  disk_size_gb = 40

  # Created empty: partitioning and mounting it is the guest's job.
  additional_disks = [
    {
      interface    = "scsi1"
      size_gb      = 200
      datastore_id = var.data_datastore_id

      # A database's data disk is usually backed up by the database, not by
      # vzdump snapshotting it underneath a running engine.
      backup = false
    },
  ]

  # One NIC with everything pinned. The MAC is fixed so that a DHCP
  # reservation, a firewall rule or a licence keyed to it survives a rebuild —
  # without it, Proxmox generates a new MAC every time the VM is recreated.
  #
  # The address is a CIDR, not a bare IP: the prefix length goes straight to
  # cloud-init, and without it the guest comes up with no netmask.
  network_devices = [
    {
      bridge       = "vmbr0"
      mac_address  = "BC:24:11:00:00:01"
      vlan_id      = 20
      ipv4_address = "192.168.20.10/24"
      ipv4_gateway = "192.168.20.1"
    },
  ]

  dns_domain  = "lan.example"
  dns_servers = ["192.168.20.1"]

  username            = "admin"
  ssh_authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]

  # Start after the network and storage VMs on a node reboot, and give the
  # database a moment before whatever starts next.
  startup = {
    order    = 10
    up_delay = 30
  }

  # The image has to carry qemu-guest-agent for this: with it on and no agent
  # installed, create and every later reboot block until agent_timeout expires.
  agent_enabled = true
}
