# Module entry point. Keep resources here while the module is small; once it
# grows past one concern, split it into files named after those concerns
# (network.tf, compute.tf, ...) and disable `terraform_standard_module_structure`
# in .tflint.hcl.
#
# Derived values belong in `locals` so that resource bodies stay declarative.

locals {
  # Tags/labels every resource in this module carries, so that a plan against an
  # untouched configuration stays empty.
  common_tags = sort(distinct(concat(["terraform"], var.tags)))

  # `cloud_image` carries exactly one of file_id/url (enforced in variables.tf),
  # so at most one of these two is non-null and coalesce always resolves.
  cloud_image_file_id = coalesce(
    var.cloud_image.file_id,
    one(proxmox_download_file.cloud_image[*].id),
  )

  # A Proxmox file ID is `datastore:content_type/file_name`, so an image passed
  # in by ID already says which content type it was stored under.
  cloud_image_content_type = (
    var.cloud_image.file_id != null
    ? try(split("/", split(":", var.cloud_image.file_id)[1])[0], "iso")
    : var.cloud_image.content_type
  )

  # The provider takes the image through a different disk attribute depending on
  # that content type, and the two are not interchangeable: `import_from` reads
  # only the `import` content type — which Proxmox enables on no storage by
  # default — while `file_id` reads `iso`, including anything that had to be
  # decompressed on the way in.
  cloud_image_is_import = local.cloud_image_content_type == "import"

  # Every bus this VM occupies. Proxmox does not report a clash — the second
  # attachment to a bus simply replaces the first — so the module checks.
  occupied_interfaces = concat(
    [var.disk_interface, var.cloud_init_interface],
    [for d in var.additional_disks : d.interface],
  )

  # The boot disk and the data disks go through one `dynamic "disk"` block, so
  # both branches have to produce the same object shape. Only the boot disk
  # carries an image; the data disks are created empty.
  disks = concat(
    [{
      interface    = var.disk_interface
      datastore_id = var.datastore_id
      size         = var.disk_size_gb
      file_format  = var.disk_file_format
      ssd          = var.disk_ssd
      discard      = var.disk_discard
      iothread     = var.disk_iothread
      backup       = var.disk_backup
      file_id      = local.cloud_image_is_import ? null : local.cloud_image_file_id
      import_from  = local.cloud_image_is_import ? local.cloud_image_file_id : null
    }],
    [for d in var.additional_disks : {
      interface    = d.interface
      datastore_id = coalesce(d.datastore_id, var.datastore_id)
      size         = d.size_gb
      file_format  = d.file_format
      ssd          = d.ssd
      discard      = d.discard
      iothread     = d.iothread
      backup       = d.backup
      file_id      = null
      import_from  = null
    }]
  )

  # `network_device` is a list attribute rather than a block, so every key the
  # provider declares has to be present — unset ones as explicit nulls.
  network_devices = [for d in var.network_devices : {
    bridge       = d.bridge
    model        = d.model
    mac_address  = d.mac_address
    vlan_id      = d.vlan_id
    mtu          = d.mtu
    firewall     = d.firewall
    disconnected = d.disconnected
    queues       = d.queues
    rate_limit   = d.rate_limit
    trunks       = d.trunks

    # Deprecated upstream, and warned about whenever it is set: drop the entry
    # from `network_devices` rather than disabling it in place.
    enabled = null
  }]

  # One entry per NIC, in the same order. "none" is turned back into an absent
  # block so that the address family is left unconfigured in the guest.
  ip_configs = [for d in var.network_devices : {
    ipv4_address = d.ipv4_address == "none" ? null : d.ipv4_address
    ipv4_gateway = d.ipv4_gateway
    ipv6_address = d.ipv6_address == "none" ? null : d.ipv6_address
    ipv6_gateway = d.ipv6_gateway
  }]

  # cloud-init only writes a DNS section when there is something to write;
  # otherwise the guest inherits whatever the Proxmox host hands out.
  dns_configured = var.dns_domain != null || length(var.dns_servers) > 0

  # --- cloud-init user-data ------------------------------------------------
  #
  # Proxmox generates the user-data from its own fields unless something hands
  # it a file, and those fields stop at creating one account: there is no way to
  # install a package or run a command through them. That is what the snippet is
  # for — `qemu-guest-agent` above all, because `agent_enabled` otherwise waits
  # `agent_timeout` for an agent the image never had.
  snippet = var.cloud_init_snippet

  # Whether the user-data comes from a file is decided by the configuration, not
  # by the upload: the file's `id` is unknown until apply, and a `for_each`
  # cannot wait for that.
  user_data_is_external = var.cloud_init_file_ids.user_data != null || var.cloud_init_snippet != null

  user_data_file_id = (
    var.cloud_init_file_ids.user_data != null
    ? var.cloud_init_file_ids.user_data
    : one(proxmox_virtual_environment_file.user_data[*].id)
  )

  # Installing the agent and starting it are two different things. `runcmd` runs
  # in cloud-init's final stage, after the package module, so the unit exists by
  # the time this fires; on an image that already shipped it, enabling an enabled
  # unit is a no-op.
  snippet_packages = local.snippet == null ? [] : distinct(concat(
    local.snippet.install_qemu_guest_agent ? ["qemu-guest-agent"] : [],
    local.snippet.packages,
  ))

  snippet_runcmd = local.snippet == null ? [] : concat(
    local.snippet.install_qemu_guest_agent ? ["systemctl enable --now qemu-guest-agent"] : [],
    local.snippet.runcmd,
  )

  # cloud-init takes a hash under `hashed_passwd` and a plaintext password under
  # `plain_text_passwd`, and a value written to the wrong one of the two leaves
  # the account unusable without reporting anything. Proxmox's own `cipassword`
  # hashes whatever it is handed unless it recognises the prefix — `$y$`
  # yescrypt it does not — which is the reason a pre-hashed password has to
  # come through the snippet instead.
  password_is_hashed = var.password == null ? false : can(regex("^[$](1|2a|2b|2y|5|6|7|y|gy)[$]", var.password))

  snippet_user = local.snippet == null || var.username == null ? null : merge(
    {
      name   = var.username
      groups = ["sudo"]
      shell  = "/bin/bash"
      sudo   = "ALL=(ALL) NOPASSWD:ALL"

      # cloud-init locks the account by default, which puts a `!` in front of the
      # hash and refuses every password login. Keys are unaffected either way, so
      # this only has to be off when there is a password to use.
      lock_passwd = var.password == null
    },
    length(var.ssh_authorized_keys) == 0 ? {} : { ssh_authorized_keys = var.ssh_authorized_keys },
    var.password == null ? {} : (
      local.password_is_hashed
      ? { hashed_passwd = var.password }
      : { plain_text_passwd = var.password }
    ),
  )

  snippet_write_files = local.snippet == null ? [] : [
    for f in local.snippet.write_files : merge(
      { path = f.path, content = f.content },
      f.permissions == null ? {} : { permissions = f.permissions },
      f.owner == null ? {} : { owner = f.owner },
      f.append == null ? {} : { append = f.append },
    )
  ]

  # Assembled as text rather than as one object: every section is a top-level
  # cloud-config mapping, so `yamlencode` per section concatenates into valid
  # YAML, and a conditional that yields a string unifies where one yielding an
  # object of a different shape would not.
  #
  # cloud-init reads a file with no `#cloud-config` line as a shell script, and
  # `yamlencode` cannot emit a comment.
  snippet_user_data = local.snippet == null ? null : join("", compact([
    "#cloud-config\n",

    # Proxmox writes the hostname into the user-data it generates, and a snippet
    # replaces that file whole, so what it carried is restated here. The address
    # and the resolver are not: those live in the network-data, which Proxmox
    # still generates from `network_devices` and `dns_*`.
    yamlencode(merge(
      {
        hostname         = var.name
        manage_etc_hosts = local.snippet.manage_etc_hosts
        package_update   = local.snippet.package_update
        package_upgrade  = local.snippet.package_upgrade
      },
      var.dns_domain == null ? {} : { fqdn = "${var.name}.${var.dns_domain}" },
    )),

    local.snippet_user == null ? "" : yamlencode({
      users = [local.snippet_user]

      # Otherwise the first login is an expired-password prompt.
      chpasswd = { expire = false }
    }),

    length(local.snippet_packages) == 0 ? "" : yamlencode({ packages = local.snippet_packages }),
    length(local.snippet_runcmd) == 0 ? "" : yamlencode({ runcmd = local.snippet_runcmd }),
    length(local.snippet_write_files) == 0 ? "" : yamlencode({ write_files = local.snippet_write_files }),
    local.snippet.ssh_pwauth == null ? "" : yamlencode({ ssh_pwauth = local.snippet.ssh_pwauth }),

    # Appended, not merged: a key this repeats becomes a duplicate YAML key
    # rather than an override.
    local.snippet.extra_yaml == null ? "" : "${trimspace(local.snippet.extra_yaml)}\n",
  ]))
}

# Downloading the image is opt-in: skipped when the caller points at a file that
# is already in a datastore. Proxmox stores it on the node, so a multi-node
# cluster downloads it once per node unless the datastore is shared.
resource "proxmox_download_file" "cloud_image" {
  count = var.cloud_image.url == null ? 0 : 1

  node_name    = var.node_name
  datastore_id = var.cloud_image.datastore_id
  content_type = var.cloud_image.content_type
  url          = var.cloud_image.url

  file_name               = var.cloud_image.file_name
  checksum                = var.cloud_image.checksum
  checksum_algorithm      = var.cloud_image.checksum_algorithm
  decompression_algorithm = var.cloud_image.decompression_algorithm
  overwrite               = var.cloud_image.overwrite
  upload_timeout          = var.cloud_image.upload_timeout
}

# Snippets are the one content type the Proxmox API refuses an upload for, so the
# provider writes this over SSH — the provider needs an `ssh` block, and the
# datastore needs `snippets` added to its content types, which Proxmox does
# nowhere by default.
resource "proxmox_virtual_environment_file" "user_data" {
  count = var.cloud_init_snippet == null ? 0 : 1

  node_name    = var.node_name
  datastore_id = var.cloud_init_snippet.datastore_id
  content_type = "snippets"

  source_raw {
    data = local.snippet_user_data

    # The file ID is built from this name and changing the ID replaces the VM, so
    # deriving it from `name` keeps an edit to the config's *contents* an
    # in-place re-upload. A booted guest will not pick that up either way:
    # cloud-init has already run.
    file_name = coalesce(var.cloud_init_snippet.file_name, "${var.name}-user-data.yaml")
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  migrate     = var.migrate
  vm_id       = var.vm_id
  description = var.description
  pool_id     = var.pool_id
  tags        = local.common_tags

  bios          = var.bios
  machine       = var.machine
  scsi_hardware = var.scsi_hardware
  boot_order    = var.boot_order == null ? [var.disk_interface] : var.boot_order

  on_boot         = var.on_boot
  started         = var.started
  stop_on_destroy = var.stop_on_destroy
  protection      = var.protection

  network_device = local.network_devices

  operating_system {
    type = var.os_type
  }

  agent {
    enabled = var.agent_enabled
    timeout = var.agent_timeout
  }

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_floating_mb
  }

  dynamic "disk" {
    for_each = local.disks
    content {
      interface    = disk.value.interface
      datastore_id = disk.value.datastore_id
      size         = disk.value.size
      file_format  = disk.value.file_format
      ssd          = disk.value.ssd
      discard      = disk.value.discard
      iothread     = disk.value.iothread
      backup       = disk.value.backup
      file_id      = disk.value.file_id
      import_from  = disk.value.import_from
    }
  }

  # UEFI needs somewhere to keep its variables, and Proxmox refuses to start an
  # ovmf VM without it.
  dynamic "efi_disk" {
    for_each = var.bios == "ovmf" ? [1] : []
    content {
      datastore_id      = var.datastore_id
      file_format       = var.disk_file_format
      type              = "4m"
      pre_enrolled_keys = false
    }
  }

  dynamic "serial_device" {
    for_each = var.serial_device_enabled ? [1] : []
    content {}
  }

  dynamic "startup" {
    for_each = var.startup == null ? [] : [var.startup]
    content {
      order      = startup.value.order
      up_delay   = startup.value.up_delay
      down_delay = startup.value.down_delay
    }
  }

  initialization {
    datastore_id = coalesce(var.cloud_init_datastore_id, var.datastore_id)
    interface    = var.cloud_init_interface
    upgrade      = var.cloud_init_upgrade

    user_data_file_id    = local.user_data_file_id
    vendor_data_file_id  = var.cloud_init_file_ids.vendor_data
    meta_data_file_id    = var.cloud_init_file_ids.meta_data
    network_data_file_id = var.cloud_init_file_ids.network_data

    # One ip_config per network device, in the same order: the nth block
    # configures the nth NIC.
    dynamic "ip_config" {
      for_each = local.ip_configs
      content {
        dynamic "ipv4" {
          for_each = ip_config.value.ipv4_address == null && ip_config.value.ipv4_gateway == null ? [] : [1]
          content {
            address = ip_config.value.ipv4_address
            gateway = ip_config.value.ipv4_gateway
          }
        }
        dynamic "ipv6" {
          for_each = ip_config.value.ipv6_address == null && ip_config.value.ipv6_gateway == null ? [] : [1]
          content {
            address = ip_config.value.ipv6_address
            gateway = ip_config.value.ipv6_gateway
          }
        }
      }
    }

    dynamic "dns" {
      for_each = local.dns_configured ? [1] : []
      content {
        domain  = var.dns_domain
        servers = length(var.dns_servers) > 0 ? var.dns_servers : null
      }
    }

    # Proxmox generates no user-data of its own once a file supplies it, so these
    # fields would be accepted and then silently ignored.
    dynamic "user_account" {
      for_each = var.username == null || local.user_data_is_external ? [] : [1]
      content {
        username = var.username
        keys     = var.ssh_authorized_keys
        password = var.password
      }
    }
  }

  lifecycle {
    # Cross-variable rules cannot live in variables.tf. Both fail at plan time,
    # before anything is created.
    precondition {
      condition     = var.username == null || length(var.ssh_authorized_keys) > 0 || var.password != null
      error_message = "The VM would have no way in: set ssh_authorized_keys, set password, or set username to null and supply your own users through cloud_init_file_ids.user_data."
    }

    precondition {
      condition     = length(distinct(local.occupied_interfaces)) == length(local.occupied_interfaces)
      error_message = "disk_interface, cloud_init_interface and every additional_disks interface must be distinct; got ${join(", ", local.occupied_interfaces)}."
    }

    precondition {
      condition     = var.cloud_init_snippet == null || var.cloud_init_file_ids.user_data == null
      error_message = "cloud_init_snippet and cloud_init_file_ids.user_data both supply the user-data, and only one file reaches the guest. Keep cloud_init_snippet to have this module render the config, or cloud_init_file_ids.user_data to point at a file you manage yourself."
    }

    precondition {
      condition     = var.cloud_init_snippet == null || var.username != null
      error_message = "cloud_init_snippet renders the account into the config it generates, so it needs username. To define users some other way, drop cloud_init_snippet and pass your own file through cloud_init_file_ids.user_data."
    }

    precondition {
      condition     = var.cloud_init_snippet == null || var.cloud_init_upgrade == null
      error_message = "cloud_init_upgrade only reaches the config Proxmox generates, and cloud_init_snippet replaces that config: set cloud_init_snippet.package_upgrade instead."
    }
  }
}
