provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # A stock Proxmox node serves the API with a self-signed certificate. Drop
  # this once the node presents one the machine running OpenTofu trusts.
  insecure = true

  # No `ssh` block: everything this module does — creating the VM, downloading
  # the image, importing it onto a disk — goes through the API. SSH is only
  # needed for uploading snippets, which this example does not do.
}

module "vm" {
  source = "../.."

  name      = "web-01"
  node_name = var.proxmox_node
  tags      = ["debian", "example"]

  # Downloaded to the node's `local` datastore on the first apply and reused
  # afterwards. Proxmox picks its handler from the file name, so a .qcow2 URL
  # has to be stored under a name ending in .img.
  #
  # `latest` in the URL is convenient and not reproducible: the file name is
  # what decides whether the image is re-fetched, so pin a release here once
  # this stops being an example.
  cloud_image = {
    url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    file_name = "debian-12-genericcloud-amd64.img"
  }

  # Everything else is left at its default: 2 cores, 2048 MiB, a 20 GiB boot
  # disk on local-lvm, and one virtio NIC on vmbr0 taking a DHCP lease.

  ssh_authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]

  # The Debian generic cloud image does not ship qemu-guest-agent, and the
  # provider blocks on create and on every reboot waiting for an agent that
  # will never answer. Turn this on once the image has one.
  agent_enabled = false
}
