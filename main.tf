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
}
