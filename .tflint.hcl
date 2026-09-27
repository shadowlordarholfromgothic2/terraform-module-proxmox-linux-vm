tflint {
  required_version = ">= 0.64"
}

config {
  format              = "compact"
  call_module_type    = "local"
  force               = false
  disabled_by_default = false
}

# Bundled ruleset — no version/source needed. `recommended` covers documented
# variables/outputs, typed variables, deprecated syntax and naming.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_unused_declarations" {
  enabled = true
}

# Expects main.tf / variables.tf / outputs.tf. Disable this if the module is
# split by concern instead (e.g. network.tf, compute.tf) rather than using a
# single main.tf.
rule "terraform_standard_module_structure" {
  enabled = true
}

# Provider-specific rulesets are opt-in: uncomment the one this module actually
# uses and pin its version. Each one is downloaded by `tflint --init`.
#
# plugin "aws" {
#   enabled = true
#   version = "0.48.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
