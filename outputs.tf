# Outputs are the module's contract. Echo back the inventory a downstream module
# needs, and mark anything credential-shaped `sensitive` — it still lands in
# state in plain text, so say so in the README.

output "name" {
  description = "Name this deployment was created under."
  value       = var.name
}

output "tags" {
  description = "Tags applied to every resource this module creates."
  value       = local.common_tags
}

output "vm_id" {
  description = "Proxmox VM ID, whether it was passed in or allocated by the host."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "node_name" {
  description = "Proxmox node the VM runs on."
  value       = proxmox_virtual_environment_vm.this.node_name
}

output "username" {
  description = "Account cloud-init created, or null when account creation was skipped."
  value       = var.username
}

output "mac_addresses" {
  description = "MAC address of each NIC, in net0..netN order — generated ones included."
  value       = proxmox_virtual_environment_vm.this.mac_addresses
}

output "ipv4_addresses" {
  description = "IPv4 addresses per guest interface, as reported by the QEMU guest agent. Empty when agent_enabled is false."
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "ipv6_addresses" {
  description = "IPv6 addresses per guest interface, as reported by the QEMU guest agent. Empty when agent_enabled is false."
  value       = proxmox_virtual_environment_vm.this.ipv6_addresses
}

output "network_interface_names" {
  description = "Interface names inside the guest, as reported by the QEMU guest agent."
  value       = proxmox_virtual_environment_vm.this.network_interface_names
}

# The static address is known at plan time; the agent-reported one is not. This
# is the address to feed an inventory or a DNS record when addressing is static.
output "configured_ipv4_address" {
  description = "IPv4 address configured on the first NIC without its prefix length, or null when that NIC uses DHCP or no IPv4 at all."
  value = try(
    local.ip_configs[0].ipv4_address == null || local.ip_configs[0].ipv4_address == "dhcp"
    ? null
    : split("/", local.ip_configs[0].ipv4_address)[0],
    null
  )
}

output "cloud_image_file_id" {
  description = "File ID of the image the boot disk was imported from, whether it was passed in or downloaded by this module."
  value       = local.cloud_image_file_id
}
