output "vm_id" {
  description = "VM ID the machine was created under."
  value       = module.vm.vm_id
}

output "cloud_init_user_data_file_id" {
  description = "The snippet the guest read. Pass the VM ID to `qm cloudinit dump <vmid> user` on the node to see what cloud-init was actually handed."
  value       = module.vm.cloud_init_user_data_file_id
}

output "ipv4_addresses" {
  description = "Addresses the guest reports through the QEMU guest agent. Populated because the snippet installed the agent — empty is the symptom of it not having worked."
  value       = module.vm.ipv4_addresses
}
