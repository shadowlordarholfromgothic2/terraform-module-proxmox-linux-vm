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

# output "credentials" {
#   description = "..."
#   value       = example_resource.this.token
#   sensitive   = true
# }
