# One run block per input the module must reject. This is pure expression
# evaluation — no Proxmox node, no API token — so it is the cheapest coverage
# in the repo and the part most likely to rot silently: a validation that stops
# rejecting something fails nothing until an apply reaches the API.
#
# The provider is mocked rather than omitted. Variable validation fails before
# any provider is configured, so most of these runs would pass without it — but
# the two precondition runs at the bottom plan the resource for real, and a
# validation that ever stops rejecting what it should would otherwise fail with
# a provider error instead of the "expected failure" message that explains what
# broke.
mock_provider "proxmox" {
  # The snippet's `id` flows into the VM's `user_data_file_id`, where the
  # provider validates it as a Proxmox file ID; an invented one is rejected.
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/test-vm-user-data.yaml"
    }
  }
}

# The smallest valid call. Each run below overrides exactly one input, so a
# failure names the rule that fired rather than the first one in the file.
variables {
  name        = "test-vm"
  node_name   = "pve"
  cloud_image = { file_id = "local:iso/debian-12.img" }
  password    = "example-password"
}

# --- identity ------------------------------------------------------------

run "rejects_uppercase_name" {
  command = plan
  variables { name = "Test-VM" }

  expect_failures = [var.name]
}

run "rejects_name_starting_with_a_digit" {
  command = plan
  variables { name = "1-vm" }

  expect_failures = [var.name]
}

run "rejects_name_over_40_characters" {
  command = plan
  variables { name = "a-very-long-machine-name-that-keeps-going-and-going" }

  expect_failures = [var.name]
}

run "rejects_empty_node_name" {
  command = plan
  variables { node_name = "  " }

  expect_failures = [var.node_name]
}

# Proxmox reserves everything below 100 for its own use.
run "rejects_reserved_vm_id" {
  command = plan
  variables { vm_id = 99 }

  expect_failures = [var.vm_id]
}

# --- cloud_image ---------------------------------------------------------

run "rejects_image_with_both_file_id_and_url" {
  command = plan
  variables {
    cloud_image = {
      file_id = "local:iso/debian-12.img"
      url     = "https://example.com/debian-12.img"
    }
  }

  expect_failures = [var.cloud_image]
}

run "rejects_image_with_neither_file_id_nor_url" {
  command = plan
  variables { cloud_image = {} }

  expect_failures = [var.cloud_image]
}

# vztmpl is an LXC template, and this module does not create containers.
run "rejects_vztmpl_content_type" {
  command = plan
  variables {
    cloud_image = {
      url          = "https://example.com/debian-12.tar.zst"
      content_type = "vztmpl"
    }
  }

  expect_failures = [var.cloud_image]
}

run "rejects_unknown_decompression_algorithm" {
  command = plan
  variables {
    cloud_image = {
      url                     = "https://example.com/debian-12.img.rar"
      decompression_algorithm = "rar"
    }
  }

  expect_failures = [var.cloud_image]
}

# The import content type takes uncompressed images only.
run "rejects_decompression_on_the_import_content_type" {
  command = plan
  variables {
    cloud_image = {
      url                     = "https://example.com/debian-12.qcow2.gz"
      content_type            = "import"
      decompression_algorithm = "gz"
    }
  }

  expect_failures = [var.cloud_image]
}

# Proxmox picks the download handler from the file name, so a URL that ends in
# a query string needs an explicit file_name.
run "rejects_url_without_a_usable_extension" {
  command = plan
  variables {
    cloud_image = { url = "https://example.com/images/download?release=12" }
  }

  expect_failures = [var.cloud_image]
}

run "rejects_checksum_without_an_algorithm" {
  command = plan
  variables {
    cloud_image = {
      url      = "https://example.com/debian-12.img"
      checksum = "d41d8cd98f00b204e9800998ecf8427e"
    }
  }

  expect_failures = [var.cloud_image]
}

# --- compute -------------------------------------------------------------

run "rejects_zero_cpu_cores" {
  command = plan
  variables { cpu_cores = 0 }

  expect_failures = [var.cpu_cores]
}

run "rejects_fractional_cpu_cores" {
  command = plan
  variables { cpu_cores = 2.5 }

  expect_failures = [var.cpu_cores]
}

run "rejects_zero_cpu_sockets" {
  command = plan
  variables { cpu_sockets = 0 }

  expect_failures = [var.cpu_sockets]
}

run "rejects_memory_below_the_qemu_floor" {
  command = plan
  variables { memory_mb = 8 }

  expect_failures = [var.memory_mb]
}

run "rejects_negative_floating_memory" {
  command = plan
  variables { memory_floating_mb = -1 }

  expect_failures = [var.memory_floating_mb]
}

# --- storage -------------------------------------------------------------

run "rejects_empty_datastore_id" {
  command = plan
  variables { datastore_id = "" }

  expect_failures = [var.datastore_id]
}

run "rejects_zero_disk_size" {
  command = plan
  variables { disk_size_gb = 0 }

  expect_failures = [var.disk_size_gb]
}

# A bus name without an index is not something Proxmox can attach to.
run "rejects_disk_interface_without_an_index" {
  command = plan
  variables { disk_interface = "scsi" }

  expect_failures = [var.disk_interface]
}

run "rejects_unknown_disk_file_format" {
  command = plan
  variables { disk_file_format = "vhdx" }

  expect_failures = [var.disk_file_format]
}

run "rejects_unknown_discard_setting" {
  command = plan
  variables { disk_discard = "off" }

  expect_failures = [var.disk_discard]
}

run "rejects_additional_disk_without_a_bus_index" {
  command = plan
  variables {
    additional_disks = [{ interface = "scsi", size_gb = 10 }]
  }

  expect_failures = [var.additional_disks]
}

run "rejects_additional_disks_sharing_a_bus" {
  command = plan
  variables {
    additional_disks = [
      { interface = "scsi1", size_gb = 10 },
      { interface = "scsi1", size_gb = 20 },
    ]
  }

  expect_failures = [var.additional_disks]
}

run "rejects_zero_sized_additional_disk" {
  command = plan
  variables {
    additional_disks = [{ interface = "scsi1", size_gb = 0 }]
  }

  expect_failures = [var.additional_disks]
}

run "rejects_unknown_additional_disk_file_format" {
  command = plan
  variables {
    additional_disks = [{ interface = "scsi1", size_gb = 10, file_format = "vhdx" }]
  }

  expect_failures = [var.additional_disks]
}

# --- network -------------------------------------------------------------

run "rejects_empty_network_devices" {
  command = plan
  variables { network_devices = [] }

  expect_failures = [var.network_devices]
}

run "rejects_dash_separated_mac" {
  command = plan
  variables {
    network_devices = [{ mac_address = "bc-24-11-00-00-01" }]
  }

  expect_failures = [var.network_devices]
}

run "rejects_short_mac" {
  command = plan
  variables {
    network_devices = [{ mac_address = "BC:24:11:00:00" }]
  }

  expect_failures = [var.network_devices]
}

# A bare address leaves the guest with no netmask: cloud-init is handed the
# prefix length verbatim.
run "rejects_ipv4_without_a_prefix_length" {
  command = plan
  variables {
    network_devices = [{ ipv4_address = "192.168.1.10" }]
  }

  expect_failures = [var.network_devices]
}

run "rejects_ipv6_without_a_prefix_length" {
  command = plan
  variables {
    network_devices = [{ ipv6_address = "2001:db8::10" }]
  }

  expect_failures = [var.network_devices]
}

run "rejects_vlan_id_above_the_802_1q_range" {
  command = plan
  variables {
    network_devices = [{ vlan_id = 4095 }]
  }

  expect_failures = [var.network_devices]
}

# The lease carries its own gateway; a second one is a silent contradiction.
run "rejects_ipv4_gateway_on_a_dhcp_interface" {
  command = plan
  variables {
    network_devices = [{ ipv4_address = "dhcp", ipv4_gateway = "192.168.1.1" }]
  }

  expect_failures = [var.network_devices]
}

run "rejects_ipv6_gateway_on_a_slaac_interface" {
  command = plan
  variables {
    network_devices = [{ ipv6_address = "auto", ipv6_gateway = "2001:db8::1" }]
  }

  expect_failures = [var.network_devices]
}

run "rejects_hostname_as_a_dns_server" {
  command = plan
  variables { dns_servers = ["ns1.lan.example"] }

  expect_failures = [var.dns_servers]
}

# --- cloud-init ----------------------------------------------------------

run "rejects_uppercase_username" {
  command = plan
  variables { username = "Admin" }

  expect_failures = [var.username]
}

run "rejects_username_starting_with_a_digit" {
  command = plan
  variables { username = "1admin" }

  expect_failures = [var.username]
}

# A path is the mistake to catch here: the module wants the key material, so
# a path would be installed verbatim as an authorized_keys line.
run "rejects_a_path_in_place_of_an_ssh_key" {
  command = plan
  variables { ssh_authorized_keys = ["~/.ssh/id_ed25519.pub"] }

  expect_failures = [var.ssh_authorized_keys]
}

run "rejects_cloud_init_interface_without_an_index" {
  command = plan
  variables { cloud_init_interface = "ide" }

  expect_failures = [var.cloud_init_interface]
}

# --- hardware and lifecycle ----------------------------------------------

run "rejects_non_duration_agent_timeout" {
  command = plan
  variables { agent_timeout = "15 minutes" }

  expect_failures = [var.agent_timeout]
}

run "rejects_unknown_bios" {
  command = plan
  variables { bios = "uefi" }

  expect_failures = [var.bios]
}

run "rejects_unknown_scsi_hardware" {
  command = plan
  variables { scsi_hardware = "virtio-scsi" }

  expect_failures = [var.scsi_hardware]
}

run "rejects_empty_boot_order" {
  command = plan
  variables { boot_order = [] }

  expect_failures = [var.boot_order]
}

# --- cloud-init snippet --------------------------------------------------

run "rejects_empty_snippet_datastore_id" {
  command = plan
  variables { cloud_init_snippet = { datastore_id = "  " } }

  expect_failures = [var.cloud_init_snippet]
}

run "rejects_a_path_as_a_snippet_file_name" {
  command = plan
  variables { cloud_init_snippet = { file_name = "snippets/user-data.yaml" } }

  expect_failures = [var.cloud_init_snippet]
}

run "rejects_an_empty_package_entry" {
  command = plan
  variables { cloud_init_snippet = { packages = ["jq", ""] } }

  expect_failures = [var.cloud_init_snippet]
}

run "rejects_an_empty_runcmd_entry" {
  command = plan
  variables { cloud_init_snippet = { runcmd = [" "] } }

  expect_failures = [var.cloud_init_snippet]
}

run "rejects_a_relative_write_files_path" {
  command = plan
  variables {
    cloud_init_snippet = {
      write_files = [{ path = "etc/motd", content = "hello" }]
    }
  }

  expect_failures = [var.cloud_init_snippet]
}

run "rejects_three_digit_write_files_permissions" {
  command = plan
  variables {
    cloud_init_snippet = {
      write_files = [{ path = "/etc/motd", content = "hello", permissions = "644" }]
    }
  }

  expect_failures = [var.cloud_init_snippet]
}

# --- preconditions -------------------------------------------------------
#
# These span more than one variable, so they live on the resource rather than
# in variables.tf, and they fail during the plan instead of before it.

run "rejects_an_account_with_no_way_to_log_in" {
  command = plan
  variables {
    username            = "admin"
    ssh_authorized_keys = []
    password            = null
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_a_data_disk_on_the_cloud_init_bus" {
  command = plan
  variables {
    cloud_init_interface = "ide2"
    additional_disks     = [{ interface = "ide2", size_gb = 10 }]
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_a_data_disk_on_the_boot_bus" {
  command = plan
  variables {
    disk_interface   = "scsi0"
    additional_disks = [{ interface = "scsi0", size_gb = 10 }]
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_a_snippet_and_a_user_data_file_together" {
  command = plan
  variables {
    cloud_init_snippet  = {}
    cloud_init_file_ids = { user_data = "local:snippets/mine.yaml" }
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_a_snippet_with_no_account_to_create" {
  command = plan
  variables {
    cloud_init_snippet = {}
    username           = null
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_cloud_init_upgrade_alongside_a_snippet" {
  command = plan
  variables {
    cloud_init_snippet = {}
    cloud_init_upgrade = true
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}
