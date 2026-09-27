output "vm_id" {
  description = "VM ID the machine was created under."
  value       = module.vm.vm_id
}

output "address" {
  description = "The machine's address. Known at plan time because the example assigns it statically — feed this to a DNS record or an inventory in the same run."
  value       = module.vm.configured_ipv4_address
}

output "ssh_command" {
  description = "Ready-made command for reaching the machine once cloud-init has finished."
  value       = "ssh ${module.vm.username}@${module.vm.configured_ipv4_address}"
}

output "ipv4_addresses" {
  description = "Every address the guest reports through the QEMU guest agent, including any the example did not assign."
  value       = module.vm.ipv4_addresses
}
