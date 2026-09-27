# Inputs are required unless they are genuinely nullable: the root module owns
# the user-facing defaults that terraform.tfvars fills in, and this module owns
# the validation, so neither is duplicated across the two.
#
# Every variable is typed and described — tflint's `recommended` preset fails the
# build otherwise. Prefer several small `validation` blocks with one specific
# error message each over a single compound condition.

variable "name" {
  description = "Name of this deployment; prefixes the resources the module creates."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 40 characters."
  }
}

variable "tags" {
  description = "Extra tags applied alongside the tags this module always sets."
  type        = list(string)
  default     = []
}

# An optional input: null is a meaningful value the module interprets, rather
# than a default the root module has to restate.
#
# variable "example_optional" {
#   description = "..."
#   type        = number
#   default     = null
#   validation {
#     condition     = var.example_optional == null ? true : var.example_optional > 0
#     error_message = "example_optional must be null or a positive number."
#   }
# }

# A structured input. `optional(...)` with a default keeps per-entry overrides
# terse at the call site.
#
# variable "example_map" {
#   description = "..."
#   type = map(object({
#     size   = string
#     labels = optional(map(string), {})
#   }))
# }
