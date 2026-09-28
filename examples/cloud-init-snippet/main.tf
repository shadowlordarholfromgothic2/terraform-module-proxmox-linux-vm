provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # A stock Proxmox node serves the API with a self-signed certificate. Drop
  # this once the node presents one the machine running OpenTofu trusts.
  insecure = true

  # Unlike the other examples, this one needs SSH: a snippet is the one content
  # type the Proxmox API refuses an upload for, so the provider writes it over
  # SFTP. `agent = true` takes the key from the running ssh-agent; swap it for
  # `private_key` if there is no agent where this runs.
  ssh {
    agent    = true
    username = var.ssh_username
  }
}

module "vm" {
  source = "../.."

  name      = "web-01"
  node_name = var.proxmox_node
  tags      = ["ubuntu", "example"]

  # Pinned to a release rather than `latest`: the file name is what decides
  # whether the image is re-fetched, so `latest` would silently keep the first
  # image it ever downloaded.
  cloud_image = {
    url       = "https://cloud-images.ubuntu.com/releases/noble/release-20240911/ubuntu-24.04-server-cloudimg-amd64.img"
    file_name = "ubuntu-24.04-server-cloudimg-amd64-20240911.img"
  }

  username            = "admin"
  ssh_authorized_keys = [trimspace(var.ssh_public_key)]

  # Passed through to cloud-init's `hashed_passwd` byte for byte. Proxmox's own
  # `cipassword` would hash it a second time unless it recognised the prefix,
  # and it does not recognise yescrypt (`$y$`) — which is the subtler reason to
  # render the config here rather than let Proxmox generate it.
  password = var.admin_password_hash

  # The point of the whole example. Ubuntu's cloud image does not ship
  # qemu-guest-agent, and Proxmox's cloud-init fields cannot install a package —
  # so `agent_enabled` below would wait out `agent_timeout` and fail the apply on
  # a VM that is up and running. `{}` alone would be enough for that; the rest
  # shows what else a real cloud-config carries.
  cloud_init_snippet = {
    datastore_id = var.snippet_datastore_id

    # On by default whenever the snippet is. Spelled out here because it is the
    # single line that makes agent_enabled work.
    install_qemu_guest_agent = true

    packages = ["nginx"]

    runcmd = [
      "systemctl enable --now nginx",
    ]

    write_files = [
      {
        path        = "/etc/nginx/conf.d/example.conf"
        content     = "server { listen 8080; return 204; }\n"
        permissions = "0644"
      },
    ]

    # Ubuntu's cloud image ships PasswordAuthentication no, so without this the
    # password above is a console login only. Leave it unset to keep it that way.
    ssh_pwauth = false

    # Appended as top-level cloud-config keys, for anything the object does not
    # model. A key repeated here is a duplicate, not an override.
    extra_yaml = "timezone: Etc/UTC"
  }

  dns_domain  = "lan.example"
  dns_servers = ["192.168.1.1"]

  # Safe to leave on, because the snippet installs the agent. The create still
  # has to finish the package install inside agent_timeout, so the guest needs a
  # working route to its mirrors.
  agent_enabled = true

  # The snippet does not replace the serial console: when cloud-init fails early
  # enough that the network never comes up, `qm terminal <vmid>` is what shows
  # why.
  serial_device_enabled = true
}
