# What the module sends to the provider, and what it hands back.
#
# The provider is mocked, so every attribute asserted below comes from
# configuration rather than from a Proxmox node. Anything whose value the host
# decides — an allocated `vm_id`, the agent-reported `ipv4_addresses`, a
# generated MAC — is deliberately not asserted, because the mock invents those.
mock_provider "proxmox" {
  # A download's `id` is computed, and left to itself the mock invents a random
  # string for it. That string then flows into the boot disk's file_id, where
  # the provider's own validator rejects it for not being a Proxmox file ID —
  # Terraform keeps the value unknown and never notices, OpenTofu generates it
  # eagerly and fails. Pinning it makes the two agree, and lets the runs below
  # assert that the downloaded image really does reach the disk.
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:iso/debian-12-genericcloud-amd64.img"
    }
  }

  # Same reason: the uploaded snippet's `id` flows into the VM's
  # `user_data_file_id`, where the provider validates it as a Proxmox file ID.
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/test-vm-user-data.yaml"
    }
  }
}

variables {
  name        = "test-vm"
  node_name   = "pve"
  cloud_image = { file_id = "local:iso/debian-12.img" }
  password    = "example-password"
}

# --- defaults ------------------------------------------------------------
#
# The defaults are a contract of their own: they are what a three-input call
# gets, and changing one silently resizes somebody's VM on the next apply.

run "defaults_are_a_working_small_vm" {
  command = plan

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.cpu).cores == 2 && one(proxmox_virtual_environment_vm.this.cpu).sockets == 1
    error_message = "The default machine must have 2 cores on 1 socket."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.memory).dedicated == 2048 && one(proxmox_virtual_environment_vm.this.memory).floating == 0
    error_message = "The default machine must have 2048 MiB dedicated and ballooning off."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).size == 20 && one(proxmox_virtual_environment_vm.this.disk).datastore_id == "local-lvm"
    error_message = "The default boot disk must be 20 GiB on local-lvm."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).interface == "scsi0" && proxmox_virtual_environment_vm.this.boot_order == tolist(["scsi0"])
    error_message = "The boot disk must default to scsi0, and boot_order must follow it."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.scsi_hardware == "virtio-scsi-single" && one(proxmox_virtual_environment_vm.this.disk).iothread
    error_message = "iothread needs virtio-scsi-single; the two defaults have to agree."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.bios == null && length(proxmox_virtual_environment_vm.this.efi_disk) == 0
    error_message = "Firmware must be left to the node default (seabios), and nothing but ovmf may bring an EFI disk."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.operating_system).type == "l26"
    error_message = "The guest OS hint must default to l26."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.agent).enabled && one(proxmox_virtual_environment_vm.this.agent).timeout == "15m"
    error_message = "The guest agent must be declared enabled with a 15m timeout."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.serial_device) == 0
    error_message = "The serial console is opt-in: the default machine must not carry a device nobody asked for."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.on_boot && proxmox_virtual_environment_vm.this.started && proxmox_virtual_environment_vm.this.stop_on_destroy && !proxmox_virtual_environment_vm.this.protection
    error_message = "The default machine must be running, start with the node, and be destroyable."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.network_device) == 1 && proxmox_virtual_environment_vm.this.network_device[0].bridge == "vmbr0"
    error_message = "The default machine must have one virtio NIC on vmbr0."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[0].model == "virtio" && proxmox_virtual_environment_vm.this.network_device[0].mac_address == null
    error_message = "The NIC must default to virtio with a Proxmox-generated MAC."
  }

  assert {
    condition     = one(one(one(proxmox_virtual_environment_vm.this.initialization).ip_config).ipv4).address == "dhcp"
    error_message = "The default NIC must be configured for DHCP."
  }

  assert {
    condition     = length(one(one(proxmox_virtual_environment_vm.this.initialization).ip_config).ipv6) == 0
    error_message = "IPv6 must be left unconfigured unless it is asked for."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.initialization).datastore_id == "local-lvm" && one(proxmox_virtual_environment_vm.this.initialization).interface == "ide2"
    error_message = "The cloud-init drive must land next to the boot disk, on ide2."
  }

  assert {
    condition     = length(one(proxmox_virtual_environment_vm.this.initialization).dns) == 0
    error_message = "With no dns_domain and no dns_servers, the guest must inherit the host's resolver rather than get an empty one."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.startup) == 0
    error_message = "A VM must stay out of the node's ordered startup sequence unless var.startup says otherwise."
  }
}

# `enabled` is deprecated upstream and warns on every plan that sets it, so the
# module has to pass it as null however the input is shaped.
run "network_device_enabled_is_never_set" {
  command = plan

  variables {
    network_devices = [{ bridge = "vmbr0" }, { bridge = "vmbr1" }]
  }

  assert {
    condition     = alltrue([for d in proxmox_virtual_environment_vm.this.network_device : d.enabled == null])
    error_message = "enabled must never reach the provider: it is deprecated and warns when set."
  }
}

# --- tags ----------------------------------------------------------------

run "tags_are_sorted_deduplicated_and_marked" {
  command = plan

  variables {
    name = "web-01"
    # "terraform" and the name repeated on purpose: a caller passing them again
    # must not produce a duplicate, which Proxmox would reject.
    tags = ["web", "debian", "terraform", "web-01"]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.tags == tolist(["debian", "terraform", "web", "web-01"])
    error_message = "Tags must be sorted and deduplicated, and always carry terraform plus the deployment name."
  }
}

# --- image routing -------------------------------------------------------
#
# The provider takes the image through a different disk attribute depending on
# its content type, and the two are not interchangeable. Getting this wrong is
# invisible at plan time against a real node, so it is asserted here.

run "an_existing_iso_image_goes_through_file_id" {
  command = plan

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).file_id == "local:iso/debian-12.img"
    error_message = "An iso-content-type image must reach the disk as file_id."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).import_from == null
    error_message = "import_from must stay unset for an iso-content-type image."
  }

  assert {
    condition     = length(proxmox_download_file.cloud_image) == 0
    error_message = "An image that is already in a datastore must not be downloaded again."
  }

  assert {
    condition     = output.cloud_image_file_id == "local:iso/debian-12.img"
    error_message = "cloud_image_file_id must echo the image that was passed in."
  }
}

# The content type is embedded in the file ID, so an import-content-type image
# has to be routed on that alone — there is no content_type input to read.
run "an_existing_import_image_is_detected_from_its_file_id" {
  command = plan

  variables {
    cloud_image = { file_id = "local:import/debian-12-genericcloud-amd64.qcow2" }
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).import_from == "local:import/debian-12-genericcloud-amd64.qcow2"
    error_message = "An import-content-type image must reach the disk as import_from."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).file_id == null
    error_message = "file_id must stay unset for an import-content-type image."
  }
}

# `apply` rather than `plan`, alone in this file: the boot disk is built from
# the download's `id`, which is computed, and a plan leaves it unknown. Against
# a mocked provider an apply touches no Proxmox node — it just resolves the
# reference so the wiring can actually be asserted.
run "a_url_is_downloaded_and_wired_into_the_boot_disk" {
  command = apply

  variables {
    cloud_image = {
      url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
      file_name = "debian-12-genericcloud-amd64.img"
      checksum  = "0000000000000000000000000000000000000000000000000000000000000000"

      checksum_algorithm = "sha256"
    }
  }

  assert {
    condition     = length(proxmox_download_file.cloud_image) == 1
    error_message = "A URL must produce exactly one download."
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).content_type == "iso"
    error_message = "Downloads must default to the iso content type, the one every Proxmox storage accepts."
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).node_name == "pve"
    error_message = "The image must be downloaded to the node the VM is created on."
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).datastore_id == "local"
    error_message = "A downloaded image must default to the local datastore."
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).checksum_algorithm == "sha256"
    error_message = "The checksum and its algorithm must be passed through to the download."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).file_id == "local:iso/debian-12-genericcloud-amd64.img"
    error_message = "The downloaded image must be what the boot disk is built from."
  }

  assert {
    condition     = output.cloud_image_file_id == "local:iso/debian-12-genericcloud-amd64.img"
    error_message = "cloud_image_file_id must report the image the module downloaded."
  }
}

run "a_compressed_image_carries_its_decompression_algorithm" {
  command = plan

  variables {
    cloud_image = {
      url                     = "https://example.com/alpine-cloud.qcow2.xz"
      file_name               = "alpine-cloud.img"
      decompression_algorithm = "zst"
    }
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).decompression_algorithm == "zst"
    error_message = "decompression_algorithm must reach the download resource."
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).content_type == "iso"
    error_message = "A compressed image has to arrive under the iso content type."
  }
}

run "the_import_content_type_routes_a_download_to_import_from" {
  command = plan

  variables {
    cloud_image = {
      url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
      content_type = "import"
    }
  }

  assert {
    condition     = one(proxmox_download_file.cloud_image).content_type == "import"
    error_message = "content_type must reach the download resource."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).file_id == null
    error_message = "A downloaded import-content-type image must not be wired to file_id."
  }
}

# --- network -------------------------------------------------------------

run "network_devices_and_their_addresses_stay_in_order" {
  command = plan

  variables {
    network_devices = [
      {
        bridge       = "vmbr0"
        mac_address  = "BC:24:11:00:00:01"
        vlan_id      = 20
        ipv4_address = "192.168.20.10/24"
        ipv4_gateway = "192.168.20.1"
      },
      {
        bridge       = "vmbr1"
        model        = "e1000"
        mtu          = 9000
        firewall     = true
        ipv4_address = "dhcp"
      },
    ]
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.network_device) == 2 && length(one(proxmox_virtual_environment_vm.this.initialization).ip_config) == 2
    error_message = "Each network_devices entry must produce one NIC and one ip_config."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[0].mac_address == "BC:24:11:00:00:01" && proxmox_virtual_environment_vm.this.network_device[0].vlan_id == 20
    error_message = "MAC and VLAN must reach net0 as given."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[1].model == "e1000" && proxmox_virtual_environment_vm.this.network_device[1].mtu == 9000 && proxmox_virtual_environment_vm.this.network_device[1].firewall
    error_message = "model, mtu and firewall must reach net1 as given."
  }

  # The nth ip_config configures the nth NIC, so a reordering bug here would
  # hand the static address to the wrong interface.
  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).ip_config[0].ipv4).address == "192.168.20.10/24"
    error_message = "The first ip_config must carry the first device's address."
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).ip_config[0].ipv4).gateway == "192.168.20.1"
    error_message = "The first ip_config must carry the first device's gateway."
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).ip_config[1].ipv4).address == "dhcp"
    error_message = "The second ip_config must carry the second device's address."
  }

  assert {
    condition     = output.configured_ipv4_address == "192.168.20.10"
    error_message = "configured_ipv4_address must be the first NIC's address without its prefix length."
  }
}

# "none" is the way to switch a family off, because an explicit null on an
# optional attribute with a default puts the default back.
run "none_switches_off_an_address_family" {
  command = plan

  variables {
    network_devices = [{
      ipv4_address = "none"
      ipv6_address = "2001:db8::10/64"
      ipv6_gateway = "2001:db8::1"
    }]
  }

  assert {
    condition     = length(one(one(proxmox_virtual_environment_vm.this.initialization).ip_config).ipv4) == 0
    error_message = "ipv4_address = \"none\" must leave the guest with no IPv4 stanza at all."
  }

  assert {
    condition     = one(one(one(proxmox_virtual_environment_vm.this.initialization).ip_config).ipv6).address == "2001:db8::10/64"
    error_message = "A static IPv6 address must reach the guest."
  }

  assert {
    condition     = output.configured_ipv4_address == null
    error_message = "configured_ipv4_address must be null when the first NIC has no IPv4."
  }
}

run "configured_ipv4_address_is_null_on_dhcp" {
  command = plan

  assert {
    condition     = output.configured_ipv4_address == null
    error_message = "configured_ipv4_address must be null on a DHCP interface: there is no address to know at plan time."
  }
}

run "the_resolver_is_written_only_when_it_is_configured" {
  command = plan

  variables {
    dns_domain  = "lan.example"
    dns_servers = ["192.168.20.1", "1.1.1.1"]
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).dns).domain == "lan.example"
    error_message = "dns_domain must reach the guest's resolver."
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).dns).servers == tolist(["192.168.20.1", "1.1.1.1"])
    error_message = "dns_servers must reach the guest's resolver in order."
  }
}

# --- storage -------------------------------------------------------------

run "data_disks_are_appended_after_the_boot_disk" {
  command = plan

  variables {
    datastore_id = "local-lvm"
    additional_disks = [
      { interface = "scsi1", size_gb = 500, datastore_id = "tank", backup = false },
      { interface = "scsi2", size_gb = 100 },
    ]
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.disk) == 3
    error_message = "The boot disk plus two data disks must produce three disks."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[0].interface == "scsi0" && proxmox_virtual_environment_vm.this.disk[0].file_id != null
    error_message = "The boot disk must come first and be the only one carrying an image."
  }

  assert {
    condition     = alltrue([for d in slice(proxmox_virtual_environment_vm.this.disk, 1, 3) : d.file_id == null && d.import_from == null])
    error_message = "Data disks must be created empty."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[1].datastore_id == "tank" && proxmox_virtual_environment_vm.this.disk[1].size == 500 && !proxmox_virtual_environment_vm.this.disk[1].backup
    error_message = "A data disk must keep its own datastore, size and backup setting."
  }

  # The common case: a data disk with no datastore of its own lands beside the
  # boot disk rather than on the provider's default.
  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[2].datastore_id == "local-lvm"
    error_message = "A data disk without a datastore_id must fall back to the VM's datastore."
  }
}

run "the_cloud_init_drive_can_live_on_its_own_datastore" {
  command = plan

  variables {
    datastore_id            = "ceph-vms"
    cloud_init_datastore_id = "local-lvm"
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.initialization).datastore_id == "local-lvm"
    error_message = "cloud_init_datastore_id must override the VM datastore for the cloud-init drive."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.disk).datastore_id == "ceph-vms"
    error_message = "The boot disk must stay on datastore_id."
  }
}

# --- firmware ------------------------------------------------------------

run "ovmf_brings_its_own_efi_disk" {
  command = plan

  variables {
    bios         = "ovmf"
    machine      = "q35"
    datastore_id = "local-lvm"
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.efi_disk) == 1
    error_message = "Proxmox refuses to start an ovmf VM without an EFI disk, so one must be created."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.efi_disk).datastore_id == "local-lvm"
    error_message = "The EFI disk must land on the VM's datastore."
  }

  # Enrolling Microsoft's keys turns on Secure Boot, and distro cloud images
  # are a coin flip on whether they are signed for it.
  assert {
    condition     = one(proxmox_virtual_environment_vm.this.efi_disk).pre_enrolled_keys == false
    error_message = "Secure Boot must stay off: a pre-enrolled EFI disk stops most cloud images from booting."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.machine == "q35"
    error_message = "machine must be passed through."
  }
}

# --- cloud-init accounts -------------------------------------------------

run "the_admin_account_carries_its_keys" {
  command = plan

  variables {
    username = "admin"
    password = null
    ssh_authorized_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyDataHere kirgo@workstation",
    ]
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).user_account).username == "admin"
    error_message = "The account cloud-init creates must be var.username."
  }

  assert {
    condition     = length(one(one(proxmox_virtual_environment_vm.this.initialization).user_account).keys) == 1
    error_message = "ssh_authorized_keys must reach the account."
  }

  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).user_account).password == null
    error_message = "With no password set, the keys must be the only way in."
  }

  assert {
    condition     = output.username == "admin"
    error_message = "The username output must name the account that was created."
  }
}

# Proxmox ignores its own user_account fields once a user-data snippet is in
# play, so the module must stop emitting the block rather than emit one that
# quietly does nothing.
run "a_custom_user_data_snippet_replaces_the_account_block" {
  command = plan

  variables {
    username = null
    cloud_init_file_ids = {
      user_data   = "local:snippets/web-01-user-data.yaml"
      vendor_data = "local:snippets/vendor-data.yaml"
    }
  }

  assert {
    condition     = length(one(proxmox_virtual_environment_vm.this.initialization).user_account) == 0
    error_message = "username = null must remove the user_account block entirely."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.initialization).user_data_file_id == "local:snippets/web-01-user-data.yaml"
    error_message = "A user-data snippet must reach the cloud-init config."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.initialization).vendor_data_file_id == "local:snippets/vendor-data.yaml"
    error_message = "A vendor-data snippet must reach the cloud-init config."
  }

  assert {
    condition     = output.username == null
    error_message = "The username output must be null when the module creates no account."
  }
}

# --- the rendered cloud-config snippet ------------------------------------
#
# The snippet is asserted by decoding it rather than by matching text: YAML
# comments and key order are not the contract, the resulting structure is.

# Applied rather than planned: the uploaded snippet's `id` is computed, so the
# mock only supplies it — and the VM's user_data_file_id only becomes known —
# once the apply has run.
run "a_snippet_carries_the_account_and_installs_the_agent" {
  command = apply

  variables {
    cloud_init_snippet  = {}
    username            = "admin"
    password            = null
    ssh_authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyDataHere kirgo@workstation"]
  }

  assert {
    condition     = one(proxmox_virtual_environment_file.user_data[0].source_raw).file_name == "test-vm-user-data.yaml"
    error_message = "The snippet's file name must default to the deployment name, so that editing its contents is not a VM replacement."
  }

  assert {
    condition     = proxmox_virtual_environment_file.user_data[0].content_type == "snippets" && proxmox_virtual_environment_file.user_data[0].datastore_id == "local"
    error_message = "The snippet must be uploaded as the snippets content type, to `local` by default."
  }

  assert {
    condition     = startswith(one(proxmox_virtual_environment_file.user_data[0].source_raw).data, "#cloud-config\n")
    error_message = "Without the #cloud-config line cloud-init reads the file as a shell script."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).hostname == "test-vm"
    error_message = "A snippet replaces the user-data Proxmox would have generated, so it has to carry the hostname itself."
  }

  assert {
    condition     = contains(yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).packages, "qemu-guest-agent")
    error_message = "Installing qemu-guest-agent is the reason the snippet exists: agent_enabled waits on it."
  }

  assert {
    condition     = contains(yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).runcmd, "systemctl enable --now qemu-guest-agent")
    error_message = "Installing the agent does not start it; the snippet has to."
  }

  assert {
    condition = (
      length(yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users) == 1 &&
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].name == "admin"
    )
    error_message = "The snippet must create var.username, and only that account."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].sudo == "ALL=(ALL) NOPASSWD:ALL"
    error_message = "The account the module creates has passwordless sudo, whichever path creates it."
  }

  assert {
    condition     = length(yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].ssh_authorized_keys) == 1
    error_message = "ssh_authorized_keys must reach the account through the snippet too."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].lock_passwd
    error_message = "With no password set the account must stay locked; the keys are the way in."
  }

  assert {
    condition     = length(one(proxmox_virtual_environment_vm.this.initialization).user_account) == 0
    error_message = "Proxmox ignores its own user_account fields once a file supplies the user-data, so the module must stop emitting the block."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.initialization).user_data_file_id == proxmox_virtual_environment_file.user_data[0].id
    error_message = "The uploaded snippet must be the file the VM boots its cloud-init from."
  }

  assert {
    condition     = output.cloud_init_user_data_file_id == proxmox_virtual_environment_file.user_data[0].id
    error_message = "The output must name the file the guest actually read."
  }
}

# The whole point of rendering the config here: Proxmox's cipassword hashes
# whatever it is handed unless it recognises the prefix, and it does not
# recognise yescrypt.
run "a_hashed_password_reaches_the_guest_unchanged" {
  command = plan

  variables {
    cloud_init_snippet = {}
    username           = "admin"
    password           = "$y$j9T$yjdfqfQoMNJEINWQQQryr1$XTCTi/ov1vAF99BPgK8s2D0IkdDOKH75iwebiaqL227"
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].hashed_passwd == "$y$j9T$yjdfqfQoMNJEINWQQQryr1$XTCTi/ov1vAF99BPgK8s2D0IkdDOKH75iwebiaqL227"
    error_message = "A crypt hash must go in under hashed_passwd, byte for byte."
  }

  assert {
    condition     = !yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].lock_passwd
    error_message = "An account with a password must be unlocked, or every password login is refused."
  }

  assert {
    condition     = !yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).chpasswd.expire
    error_message = "Without chpasswd.expire = false the first login is an expired-password prompt."
  }
}

run "a_plaintext_password_goes_in_as_plaintext" {
  command = plan

  variables {
    cloud_init_snippet = {}
    username           = "admin"
    password           = "example-password"
  }

  assert {
    condition = (
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].plain_text_passwd == "example-password" &&
      !can(yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).users[0].hashed_passwd)
    )
    error_message = "A password that is not a crypt hash must go in under plain_text_passwd; cloud-init reads hashed_passwd as a hash and would leave the account unusable."
  }
}

run "snippet_extras_reach_the_cloud_config" {
  command = plan

  variables {
    username   = "admin"
    dns_domain = "lan.example"
    cloud_init_snippet = {
      datastore_id             = "tank"
      file_name                = "db-01-ci.yaml"
      install_qemu_guest_agent = false
      package_upgrade          = true
      packages                 = ["postgresql-16", "jq"]
      runcmd                   = ["systemctl enable postgresql"]
      ssh_pwauth               = false
      write_files = [
        {
          path        = "/etc/sysctl.d/99-db.conf"
          content     = "vm.swappiness = 1\n"
          permissions = "0644"
        },
      ]
      extra_yaml = "timezone: Europe/Berlin"
    }
  }

  assert {
    condition     = proxmox_virtual_environment_file.user_data[0].datastore_id == "tank" && one(proxmox_virtual_environment_file.user_data[0].source_raw).file_name == "db-01-ci.yaml"
    error_message = "The snippet's datastore and file name must be overridable."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).fqdn == "test-vm.lan.example"
    error_message = "dns_domain must reach the snippet as the fqdn, the way Proxmox would have written it."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).packages == ["postgresql-16", "jq"]
    error_message = "install_qemu_guest_agent = false must leave the agent out and the caller's packages in, in order."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).runcmd == ["systemctl enable postgresql"]
    error_message = "install_qemu_guest_agent = false must not prepend the agent's start command."
  }

  assert {
    condition = (
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).package_upgrade &&
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).package_update
    )
    error_message = "package_upgrade must reach the config, and package_update has to be on or the install runs against a stale index."
  }

  assert {
    condition = (
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).write_files[0].path == "/etc/sysctl.d/99-db.conf" &&
      yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).write_files[0].permissions == "0644"
    )
    error_message = "write_files must reach the config with its permissions kept a string."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).ssh_pwauth == false
    error_message = "ssh_pwauth must reach the config: an Ubuntu cloud image ships with password logins off, so a password alone is a console-only login."
  }

  assert {
    condition     = yamldecode(one(proxmox_virtual_environment_file.user_data[0].source_raw).data).timezone == "Europe/Berlin"
    error_message = "extra_yaml must be appended to the config as top-level cloud-config keys."
  }
}

run "no_snippet_leaves_the_native_fields_in_charge" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_file.user_data) == 0
    error_message = "Nothing may be uploaded when cloud_init_snippet is null: the snippets content type is off by default and the upload would fail."
  }

  # Asserted on the module's own value rather than on the resource: the provider
  # marks user_data_file_id optional *and* computed, so the mock invents one when
  # the configuration leaves it unset.
  assert {
    condition     = local.user_data_file_id == null
    error_message = "With no snippet and no file passed in, Proxmox must generate the user-data itself."
  }

  # var.username is left at its default here, which is the other half of what
  # this asserts. A failure prints "(sensitive value)" for the account: the file
  # sets a password, and that mark spreads over the whole block on the way out.
  assert {
    condition     = one(one(proxmox_virtual_environment_vm.this.initialization).user_account).username == "ubuntu"
    error_message = "The native user_account path must survive the snippet being opt-in, and must default to the ubuntu account."
  }
}

# --- lifecycle knobs -----------------------------------------------------

run "lifecycle_inputs_reach_the_provider" {
  command = plan

  variables {
    vm_id                 = 9001
    description           = "Managed by OpenTofu"
    pool_id               = "homelab"
    migrate               = true
    started               = false
    on_boot               = false
    protection            = true
    stop_on_destroy       = false
    agent_enabled         = false
    serial_device_enabled = true
    memory_floating_mb    = 1024
    boot_order            = ["scsi0", "net0"]
    startup               = { order = 10, up_delay = 30 }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.vm_id == 9001 && proxmox_virtual_environment_vm.this.pool_id == "homelab" && proxmox_virtual_environment_vm.this.description == "Managed by OpenTofu"
    error_message = "Identity inputs must be passed through."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.migrate && proxmox_virtual_environment_vm.this.protection && !proxmox_virtual_environment_vm.this.started && !proxmox_virtual_environment_vm.this.on_boot && !proxmox_virtual_environment_vm.this.stop_on_destroy
    error_message = "Lifecycle flags must be passed through."
  }

  assert {
    condition     = !one(proxmox_virtual_environment_vm.this.agent).enabled
    error_message = "agent_enabled = false must be passed through: an image without the agent hangs the apply otherwise."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this.serial_device) == 1
    error_message = "serial_device_enabled = true must attach the serial console: it is the only way in when the network config is wrong."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.memory).floating == 1024
    error_message = "memory_floating_mb must enable ballooning."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.boot_order == tolist(["scsi0", "net0"])
    error_message = "An explicit boot_order must override the default."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.this.startup).order == 10 && one(proxmox_virtual_environment_vm.this.startup).up_delay == 30
    error_message = "startup must reach the provider."
  }

  assert {
    condition     = output.vm_id == 9001 && output.node_name == "pve" && output.name == "test-vm"
    error_message = "The identity outputs must echo the machine that was planned."
  }
}
