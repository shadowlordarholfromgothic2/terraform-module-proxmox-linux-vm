<!--
README template. Replace every <placeholder>, delete the sections that do not
apply to this module, and delete these comments. The section order is
deliberate: what it is, what it needs, how to call it, its contract (inputs and
outputs), then the things that will surprise whoever inherits it.
-->

# &lt;module-name&gt;

&lt;One paragraph: what this module provisions, on what platform, and what the
caller gets back. Name the technology with a link on first mention.&gt;

&lt;A second paragraph on scope: what the module deliberately does *not* expose,
and the shape of the input that decides how much it creates — so a reader knows
whether it fits before reading the input table.&gt;

## What it does

&lt;A numbered list of the apply, in order. This is the section that tells a
reviewer whether the module does what its name claims.&gt;

1. &lt;First thing, naming the input that drives it.&gt;
2. &lt;...&gt;
3. &lt;...&gt;

## Requirements

| Name | Version |
| --- | --- |
| terraform / opentofu | `>= 1.9.0, < 2.0.0` |
| [&lt;provider&gt;](https://registry.terraform.io/providers/&lt;namespace&gt;/&lt;provider&gt;) | `&lt;version&gt;` |

&lt;Say why any provider is pinned exactly rather than floating — normally because
its resource schema moves between minor releases.&gt;

This module declares no `provider` blocks — it inherits the configured instances
from the root module, which is where credentials belong.

### Environment prerequisites

&lt;Everything that must exist before the first apply and that the module will not
create. Be specific about what breaks if it is missing.&gt;

- &lt;Credentials, and the permissions they need.&gt;
- &lt;Pre-existing infrastructure the inputs reference by name.&gt;
- &lt;Anything that has to be reserved or free — addresses, ports, names.&gt;

## Usage

&lt;State whether the example is minimal or illustrative, so nobody copies an
example value into production by accident.&gt;

```hcl
module "<module_name>" {
  source = "./modules/<module-name>"

  name = "<example>"
  tags = ["<example>"]
}
```

&lt;Any post-apply step, as a shell transcript:&gt;

```console
$ tofu output -raw <output> > <path>
```

## Inputs

&lt;One sentence on the defaults policy — which inputs have defaults and why the
rest are required.&gt;

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `name` | Name of this deployment; prefixes the resources the module creates. | `string` | n/a |
| `tags` | Extra tags applied alongside the tags this module always sets. | `list(string)` | `[]` |

<!--
Give any non-trivial object or map input its own subsection: the type as HCL,
what the map key means, what validation actually enforces, and the shapes that
are legal but a bad idea.

### `<input>`

```hcl
map(object({
  size   = string                     # <what it means>
  labels = optional(map(string), {})  # <what it means>
}))
```

The map key becomes &lt;...&gt;, so it must be &lt;constraint&gt;.
-->

## Outputs

| Name | Description | Sensitive |
| --- | --- | --- |
| `name` | Name this deployment was created under. | no |
| `tags` | Tags applied to every resource this module creates. | no |

&lt;If any output is sensitive: name the backend requirement, because sensitive
outputs are still plain text in state.&gt;

## Resources created

| Address | Purpose |
| --- | --- |
| `&lt;resource_type.name&gt;` | &lt;What it is, and what names it.&gt; |

## Baked-in decisions

&lt;Things this module fixes rather than exposing as variables. Each entry is a
decision someone will eventually want to change — say what it is and why it is
this way, so they can judge whether to lift it into a variable.&gt;

- **&lt;Decision&gt;** — &lt;reasoning&gt;.

## Lifecycle notes

&lt;What happens on the second and later applies: the changes that are disruptive,
the ones that are one-way, and the manual steps that have to happen outside
Terraform. This is the most valuable section in the file — write it from the
incidents, not from the code.&gt;

- **&lt;Short claim.&gt;** &lt;What actually happens, and what to do instead.&gt;

## Layout

| File | Contents |
| --- | --- |
| [variables.tf](variables.tf) | Inputs and all validation. |
| [main.tf](main.tf) | Locals and the resources. |
| [outputs.tf](outputs.tf) | The module's contract. |
| [versions.tf](versions.tf) | Terraform and provider constraints. |

## Development

Commits on `main` follow [Conventional
Commits](https://www.conventionalcommits.org/en/v1.0.0/): the subject prefix
decides the CHANGELOG section and the version bump. `feat:` and `fix:` are the
ones that produce a release; `chore:`, `style:` and `test:` are hidden from the
changelog.

- **Validate** (`.github/workflows/terraform-validate.yml`) runs on every pull
  request: `terraform fmt -check`, `terraform validate` against both the version
  floor from [versions.tf](versions.tf) and the current release, the same
  validate under OpenTofu, and `tflint` with
  [.tflint.hcl](.tflint.hcl). Run the same checks locally:

  ```console
  $ terraform fmt -recursive
  $ terraform init -backend=false && terraform validate
  $ tflint --init && tflint -f compact --recursive
  ```

- **Release** (`.github/workflows/release.yml`) runs
  [release-please](https://github.com/googleapis/release-please) on `main`. It
  keeps a release PR open that accumulates `CHANGELOG.md` entries; merging that
  PR writes the changelog, bumps
  [.release-please-manifest.json](.release-please-manifest.json) and tags the
  release as `v<version>`. While the major version is `0`,
  `bump-minor-pre-major` turns a breaking change into a minor bump rather than
  `1.0.0`.

Set `package-name` in
[.release-please-config.json](.release-please-config.json) to this module's name
before the first release.
