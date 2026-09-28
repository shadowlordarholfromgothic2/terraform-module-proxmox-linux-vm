# Inputs are required unless they are genuinely nullable: the root module owns
# the user-facing defaults that terraform.tfvars fills in, and this module owns
# the validation, so neither is duplicated across the two.
#
# Every variable is typed and described — tflint's `recommended` preset fails the
# build otherwise. Prefer several small `validation` blocks with one specific
# error message each over a single compound condition.
#
# Rules that span two variables cannot live here; they are `precondition`
# blocks on the VM resource in main.tf.

# --------------------------------------------------------------------------
# Placement and identity
# --------------------------------------------------------------------------

variable "name" {
  description = "Name of this deployment; becomes the VM name and its cloud-init hostname."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 40 characters."
  }
}

variable "node_name" {
  description = "Proxmox VE node the VM is created on."
  type        = string
  validation {
    condition     = length(trimspace(var.node_name)) > 0
    error_message = "node_name must not be empty."
  }
}

variable "migrate" {
  description = "Live-migrate the VM when node_name changes, instead of destroying and recreating it on the new node. Needs shared or replicated storage to be worth anything."
  type        = bool
  default     = false
}

variable "vm_id" {
  description = "Fixed VM ID to claim. Null lets Proxmox allocate the next free ID."
  type        = number
  default     = null
  validation {
    condition     = var.vm_id == null ? true : var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "vm_id must be null or between 100 and 999999999; Proxmox reserves everything below 100."
  }
}

variable "description" {
  description = "Free-text note shown in the Proxmox UI."
  type        = string
  default     = null
}

variable "pool_id" {
  description = "Existing Proxmox resource pool to place the VM in. Null leaves it unpooled."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags applied alongside the tags this module always sets."
  type        = list(string)
  default     = []
}

# --------------------------------------------------------------------------
# Cloud image
# --------------------------------------------------------------------------

variable "cloud_image" {
  description = "Source cloud image for the boot disk: either a file already in a datastore (`file_id`) or a URL this module downloads (`url`). Exactly one of the two."
  type = object({
    file_id                 = optional(string)
    url                     = optional(string)
    datastore_id            = optional(string, "local")
    content_type            = optional(string, "iso")
    file_name               = optional(string)
    checksum                = optional(string)
    checksum_algorithm      = optional(string)
    decompression_algorithm = optional(string)
    overwrite               = optional(bool, false)
    upload_timeout          = optional(number)
  })

  validation {
    condition     = (var.cloud_image.file_id == null) != (var.cloud_image.url == null)
    error_message = "cloud_image must set exactly one of file_id or url."
  }

  validation {
    condition     = contains(["iso", "import"], var.cloud_image.content_type)
    error_message = "cloud_image.content_type must be iso or import. `vztmpl` is for LXC templates, which this module does not create."
  }

  validation {
    condition     = var.cloud_image.decompression_algorithm == null ? true : contains(["gz", "lzo", "zst", "bz2"], var.cloud_image.decompression_algorithm)
    error_message = "cloud_image.decompression_algorithm must be null, gz, lzo, zst or bz2."
  }

  validation {
    condition     = var.cloud_image.decompression_algorithm == null || var.cloud_image.content_type == "iso"
    error_message = "A compressed image has to be downloaded with cloud_image.content_type = \"iso\": the import content type takes uncompressed images only."
  }

  validation {
    condition = var.cloud_image.url == null ? true : can(regex(
      "\\.(img|iso|qcow2|raw|vma|zst|gz|xz|bz2)$",
      coalesce(var.cloud_image.file_name, var.cloud_image.url)
    ))
    error_message = "Proxmox rejects downloads whose file name has no recognised extension; set cloud_image.file_name to something ending in .img or .iso when the URL does not."
  }

  validation {
    condition     = var.cloud_image.checksum == null || var.cloud_image.checksum_algorithm != null
    error_message = "cloud_image.checksum_algorithm is required whenever cloud_image.checksum is set (md5, sha1, sha224, sha256, sha384, sha512)."
  }
}

# --------------------------------------------------------------------------
# Compute
# --------------------------------------------------------------------------

variable "cpu_cores" {
  description = "Cores per socket."
  type        = number
  default     = 2
  validation {
    condition     = var.cpu_cores >= 1 && floor(var.cpu_cores) == var.cpu_cores
    error_message = "cpu_cores must be a whole number of at least 1."
  }
}

variable "cpu_sockets" {
  description = "Number of CPU sockets; total vCPUs are cpu_cores * cpu_sockets."
  type        = number
  default     = 1
  validation {
    condition     = var.cpu_sockets >= 1 && floor(var.cpu_sockets) == var.cpu_sockets
    error_message = "cpu_sockets must be a whole number of at least 1."
  }
}

variable "cpu_type" {
  description = "Emulated CPU model, e.g. `x86-64-v2-AES`, `host`, `kvm64`. `host` is fastest but pins the VM to compatible hardware for live migration."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "memory_mb" {
  description = "Memory dedicated to the VM, in MiB."
  type        = number
  default     = 2048
  validation {
    condition     = var.memory_mb >= 16 && floor(var.memory_mb) == var.memory_mb
    error_message = "memory_mb must be a whole number of at least 16."
  }
}

variable "memory_floating_mb" {
  description = "Ballooning floor in MiB. 0 disables ballooning; any other value must be at most memory_mb and turns memory_mb into the ceiling."
  type        = number
  default     = 0
  validation {
    condition     = var.memory_floating_mb >= 0 && floor(var.memory_floating_mb) == var.memory_floating_mb
    error_message = "memory_floating_mb must be a whole number of 0 or more."
  }
}

# --------------------------------------------------------------------------
# Storage
# --------------------------------------------------------------------------

variable "datastore_id" {
  description = "Datastore holding the boot disk, the cloud-init drive and the EFI disk."
  type        = string
  default     = "local-lvm"
  validation {
    condition     = length(trimspace(var.datastore_id)) > 0
    error_message = "datastore_id must not be empty."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GiB. It must be at least the size of the cloud image; the image is grown to match on import."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 1 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number of at least 1."
  }
}

variable "disk_interface" {
  description = "Bus the boot disk attaches to, e.g. `scsi0`, `virtio0`, `sata0`."
  type        = string
  default     = "scsi0"
  validation {
    condition     = can(regex("^(scsi|virtio|sata|ide)[0-9]+$", var.disk_interface))
    error_message = "disk_interface must be a bus name with an index, such as scsi0, virtio0, sata0 or ide0."
  }
}

variable "disk_file_format" {
  description = "On-disk format for the boot disk. Null takes the datastore default: `raw` on block storage (LVM, ZFS, Ceph), `qcow2` on directory storage."
  type        = string
  default     = null
  validation {
    condition     = var.disk_file_format == null ? true : contains(["raw", "qcow2", "vmdk"], var.disk_file_format)
    error_message = "disk_file_format must be null, raw, qcow2 or vmdk."
  }
}

variable "disk_ssd" {
  description = "Advertise the boot disk to the guest as an SSD. Ignored by the virtio bus."
  type        = bool
  default     = true
}

variable "disk_discard" {
  description = "Pass guest TRIM through to the datastore so deletes reclaim space. `on` or `ignore`."
  type        = string
  default     = "on"
  validation {
    condition     = contains(["on", "ignore"], var.disk_discard)
    error_message = "disk_discard must be on or ignore."
  }
}

variable "disk_iothread" {
  description = "Give the boot disk its own I/O thread. Requires a scsi or virtio bus, and scsi_hardware set to virtio-scsi-single for scsi."
  type        = bool
  default     = true
}

variable "disk_backup" {
  description = "Include the boot disk in vzdump backups of this VM."
  type        = bool
  default     = true
}

variable "additional_disks" {
  description = "Extra empty data disks attached after the boot disk. See the README for the object shape."
  type = list(object({
    interface    = string
    size_gb      = number
    datastore_id = optional(string)
    file_format  = optional(string)
    ssd          = optional(bool, false)
    discard      = optional(string, "on")
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
  }))
  default = []

  validation {
    condition = alltrue([
      for d in var.additional_disks : can(regex("^(scsi|virtio|sata|ide)[0-9]+$", d.interface))
    ])
    error_message = "Every additional_disks entry needs an interface like scsi1, virtio1 or sata0."
  }

  validation {
    condition     = length(distinct([for d in var.additional_disks : d.interface])) == length(var.additional_disks)
    error_message = "additional_disks entries must not share an interface with each other."
  }

  validation {
    condition     = alltrue([for d in var.additional_disks : d.size_gb >= 1 && floor(d.size_gb) == d.size_gb])
    error_message = "Every additional_disks entry needs a whole size_gb of at least 1."
  }

  validation {
    condition = alltrue([
      for d in var.additional_disks : d.file_format == null ? true : contains(["raw", "qcow2", "vmdk"], d.file_format)
    ])
    error_message = "additional_disks file_format must be null, raw, qcow2 or vmdk."
  }
}

# --------------------------------------------------------------------------
# Network
# --------------------------------------------------------------------------

variable "network_devices" {
  description = "Virtual NICs in order — the first becomes net0/eth0 — each carrying its own cloud-init addressing. Addresses are `dhcp`, `none`, or CIDR; ipv6 also takes `auto` for SLAAC. See the README for the object shape."
  type = list(object({
    bridge       = optional(string, "vmbr0")
    model        = optional(string, "virtio")
    mac_address  = optional(string)
    vlan_id      = optional(number)
    mtu          = optional(number)
    firewall     = optional(bool, false)
    disconnected = optional(bool, false)
    queues       = optional(number)
    rate_limit   = optional(number)
    trunks       = optional(string)

    # "none" rather than null is how an address family is switched off: for an
    # optional attribute that has a default, Terraform reads an explicit null as
    # "unset" and puts the default back.
    ipv4_address = optional(string, "dhcp")
    ipv4_gateway = optional(string)
    ipv6_address = optional(string, "none")
    ipv6_gateway = optional(string)
  }))
  default = [{}]

  validation {
    condition     = length(var.network_devices) >= 1 && length(var.network_devices) <= 32
    error_message = "network_devices must hold between 1 and 32 entries."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      d.mac_address == null ? true : can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", d.mac_address))
    ])
    error_message = "network_devices mac_address must be six colon-separated hex pairs, e.g. BC:24:11:00:00:01. Leave it null to let Proxmox generate one."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      contains(["dhcp", "none"], coalesce(d.ipv4_address, "none")) || can(cidrnetmask(d.ipv4_address))
    ])
    error_message = "network_devices ipv4_address must be \"dhcp\", \"none\", or an address with a prefix length such as 192.168.1.10/24 — a bare IP leaves the guest without a netmask."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      contains(["dhcp", "auto", "none"], coalesce(d.ipv6_address, "none")) || can(cidrhost(d.ipv6_address, 0))
    ])
    error_message = "network_devices ipv6_address must be \"dhcp\", \"auto\", \"none\", or an address with a prefix length such as 2001:db8::10/64."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      d.vlan_id == null ? true : d.vlan_id >= 1 && d.vlan_id <= 4094
    ])
    error_message = "network_devices vlan_id must be null or between 1 and 4094."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      d.ipv4_gateway == null || !contains(["dhcp", "none"], coalesce(d.ipv4_address, "none"))
    ])
    error_message = "network_devices ipv4_gateway needs a static ipv4_address: a DHCP lease carries its own gateway, and \"none\" leaves the family unconfigured."
  }

  validation {
    condition = alltrue([
      for d in var.network_devices :
      d.ipv6_gateway == null || !contains(["dhcp", "auto", "none"], coalesce(d.ipv6_address, "none"))
    ])
    error_message = "network_devices ipv6_gateway needs a static ipv6_address: DHCPv6 and SLAAC carry their own gateway, and \"none\" leaves the family unconfigured."
  }
}

variable "dns_domain" {
  description = "Search domain written into the guest's resolver. Null inherits the Proxmox host's setting."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "Nameservers written into the guest's resolver. Empty inherits the Proxmox host's setting."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.dns_servers : can(cidrhost("${s}/32", 0)) || can(cidrhost("${s}/128", 0))])
    error_message = "dns_servers entries must be bare IPv4 or IPv6 addresses."
  }
}

# --------------------------------------------------------------------------
# Cloud-init
# --------------------------------------------------------------------------

variable "username" {
  description = "Login account cloud-init creates, with passwordless sudo. Set to null to skip account creation entirely, which is what you want when cloud_init_file_ids.user_data supplies its own users."
  type        = string
  default     = "ubuntu"
  validation {
    condition     = var.username == null ? true : can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.username))
    error_message = "username must be a valid Linux account name: lowercase, starting with a letter or underscore, at most 32 characters."
  }
}

variable "ssh_authorized_keys" {
  description = "Public keys installed into the account's authorized_keys. Give the full key line, not a path."
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for k in var.ssh_authorized_keys :
      can(regex("^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\\.com)\\s+\\S+", trimspace(k)))
    ])
    error_message = "Each ssh_authorized_keys entry must be a full public key line such as \"ssh-ed25519 AAAA... comment\" — reading a .pub file with file() is the usual way to get one."
  }
}

variable "password" {
  description = "Password for the account. Null leaves it unset, so the keys are the only way in. It is stored in state in plain text."
  type        = string
  default     = null
  sensitive   = true
}

variable "cloud_init_datastore_id" {
  description = "Datastore for the generated cloud-init drive. Null puts it next to the boot disk on datastore_id."
  type        = string
  default     = null
}

variable "cloud_init_interface" {
  description = "Bus the cloud-init drive attaches to. Keep it clear of disk_interface and of every additional_disks interface."
  type        = string
  default     = "ide2"
  validation {
    condition     = can(regex("^(scsi|virtio|sata|ide)[0-9]+$", var.cloud_init_interface))
    error_message = "cloud_init_interface must be a bus name with an index, such as ide2."
  }
}

variable "cloud_init_upgrade" {
  description = "Run a package upgrade on first boot. Null takes the provider default (enabled). False is the reproducible choice — bake updates into the image instead."
  type        = bool
  default     = null
}

variable "cloud_init_file_ids" {
  description = "Snippet file IDs that override the generated cloud-init config, e.g. `local:snippets/user-data.yaml`. Each requires the datastore to allow the `snippets` content type."
  type = object({
    user_data    = optional(string)
    vendor_data  = optional(string)
    meta_data    = optional(string)
    network_data = optional(string)
  })
  default = {}
}

variable "cloud_init_snippet" {
  description = "Render the user-data as a cloud-config snippet this module uploads, instead of leaving it to Proxmox. Null keeps Proxmox's own fields, which can create one account and nothing more — no packages, no commands. `{}` takes the defaults, which install and start qemu-guest-agent. Needs a datastore with the `snippets` content type and a working `ssh` block on the provider."
  type = object({
    datastore_id             = optional(string, "local")
    file_name                = optional(string)
    install_qemu_guest_agent = optional(bool, true)
    package_update           = optional(bool, true)
    package_upgrade          = optional(bool, false)
    packages                 = optional(list(string), [])
    runcmd                   = optional(list(string), [])
    write_files = optional(list(object({
      path        = string
      content     = string
      permissions = optional(string)
      owner       = optional(string)
      append      = optional(bool)
    })), [])
    manage_etc_hosts = optional(bool, true)
    ssh_pwauth       = optional(bool)
    extra_yaml       = optional(string)
  })
  default = null

  validation {
    condition     = var.cloud_init_snippet == null ? true : length(trimspace(var.cloud_init_snippet.datastore_id)) > 0
    error_message = "cloud_init_snippet.datastore_id must not be empty; it has to name a datastore with the `snippets` content type enabled."
  }

  validation {
    condition = var.cloud_init_snippet == null ? true : (
      var.cloud_init_snippet.file_name == null
      ? true
      : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.cloud_init_snippet.file_name))
    )
    error_message = "cloud_init_snippet.file_name must be a bare file name of letters, digits, dots, dashes and underscores: it names a file inside the datastore's snippets directory, not a path to one."
  }

  validation {
    condition     = var.cloud_init_snippet == null ? true : alltrue([for p in var.cloud_init_snippet.packages : length(trimspace(p)) > 0])
    error_message = "cloud_init_snippet.packages must not hold empty entries."
  }

  validation {
    condition     = var.cloud_init_snippet == null ? true : alltrue([for c in var.cloud_init_snippet.runcmd : length(trimspace(c)) > 0])
    error_message = "cloud_init_snippet.runcmd must not hold empty entries."
  }

  validation {
    condition     = var.cloud_init_snippet == null ? true : alltrue([for f in var.cloud_init_snippet.write_files : startswith(f.path, "/")])
    error_message = "Every cloud_init_snippet.write_files path must be absolute: cloud-init has no working directory to resolve a relative one against."
  }

  validation {
    condition = var.cloud_init_snippet == null ? true : alltrue([
      for f in var.cloud_init_snippet.write_files :
      f.permissions == null ? true : can(regex("^0[0-7]{3}$", f.permissions))
    ])
    error_message = "cloud_init_snippet.write_files permissions must be a four-digit octal string such as \"0644\" — YAML reads an unquoted 644 as decimal."
  }
}

# --------------------------------------------------------------------------
# Guest agent and lifecycle
# --------------------------------------------------------------------------

variable "agent_enabled" {
  description = "Tell Proxmox the QEMU guest agent is present. The agent has to actually be installed in the image, or every create and reboot blocks until agent_timeout expires."
  type        = bool
  default     = true
}

variable "agent_timeout" {
  description = "How long to wait for the guest agent to answer, as a Go duration."
  type        = string
  default     = "15m"
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h)$", var.agent_timeout))
    error_message = "agent_timeout must be a Go duration such as 30s, 5m or 1h."
  }
}

variable "started" {
  description = "Keep the VM running. False stops it on the next apply without destroying it."
  type        = bool
  default     = true
}

variable "on_boot" {
  description = "Start the VM automatically when the Proxmox node boots."
  type        = bool
  default     = true
}

variable "stop_on_destroy" {
  description = "Hard-stop the VM on destroy instead of asking the guest to shut down. False is graceful but waits on the guest."
  type        = bool
  default     = true
}

variable "protection" {
  description = "Set the Proxmox protection flag, which makes the host refuse to remove the VM or its disks. A destroy then fails until it is cleared."
  type        = bool
  default     = false
}

variable "startup" {
  description = "Node boot ordering. Null leaves the VM out of the ordered startup sequence."
  type = object({
    order      = optional(number)
    up_delay   = optional(number)
    down_delay = optional(number)
  })
  default = null
}

# --------------------------------------------------------------------------
# Firmware and hardware
# --------------------------------------------------------------------------

variable "bios" {
  description = "Firmware the VM boots with. `ovmf` also creates an EFI disk on datastore_id; the cloud image has to be UEFI-bootable."
  type        = string
  default     = null
  validation {
    condition     = var.bios == null ? true : contains(["seabios", "ovmf"], var.bios)
    error_message = "bios must be seabios or ovmf."
  }
}

variable "machine" {
  description = "QEMU machine type, e.g. `q35`. Null takes the provider default (i440fx)."
  type        = string
  default     = null
}

variable "scsi_hardware" {
  description = "SCSI controller model. `virtio-scsi-single` is what disk_iothread needs."
  type        = string
  default     = "virtio-scsi-single"
  validation {
    condition = contains([
      "lsi", "lsi53c810", "virtio-scsi-pci", "virtio-scsi-single", "megasas", "pvscsi"
    ], var.scsi_hardware)
    error_message = "scsi_hardware must be one of: lsi, lsi53c810, virtio-scsi-pci, virtio-scsi-single, megasas, pvscsi."
  }
}

variable "os_type" {
  description = "Guest OS hint Proxmox uses to pick device defaults. `l26` covers every 2.6+ Linux kernel."
  type        = string
  default     = "l26"
}

variable "boot_order" {
  description = "Boot device order by interface name. Null boots from disk_interface alone."
  type        = list(string)
  default     = null
  validation {
    condition     = var.boot_order == null ? true : length(var.boot_order) > 0
    error_message = "boot_order must be null or hold at least one interface name."
  }
}

variable "serial_device_enabled" {
  description = "Attach a serial console. Most cloud images log their boot to it, so leaving this on is what makes `qm terminal` useful when the network config is wrong."
  type        = bool
  default     = false
}
