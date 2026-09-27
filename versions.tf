terraform {
  # Keep the floor in step with the pinned entry in the Validate workflow's
  # matrix: CI proves the constraint this module advertises is true.
  required_version = ">= 1.9.0, < 2.0.0"

  # Provider *configuration* stays in the root module; a child module only
  # declares which providers it needs so it inherits the root's instances.
  #
  # Pin exactly where the resource schema moves between minor releases, and use
  # `~>` where the provider is stable enough to float.
  required_providers {
    # example = {
    #   source  = "namespace/example"
    #   version = "1.2.3"
    # }
  }
}
