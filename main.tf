# Module entry point. Keep resources here while the module is small; once it
# grows past one concern, split it into files named after those concerns
# (network.tf, compute.tf, ...) and disable `terraform_standard_module_structure`
# in .tflint.hcl.
#
# Derived values belong in `locals` so that resource bodies stay declarative.

locals {
  # Tags/labels every resource in this module carries, so that a plan against an
  # untouched configuration stays empty.
  common_tags = sort(distinct(concat(["opentofu", var.name], var.tags)))

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

    user_data_file_id    = var.cloud_init_file_ids.user_data
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

    dynamic "user_account" {
      for_each = var.username == null ? [] : [1]
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
  }
}
