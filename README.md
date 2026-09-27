# terraform-module-proxmox-linux-vm

Creates a single Linux virtual machine on a [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment/overview)
node from a cloud image, using the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
provider. The image is imported onto a fresh boot disk, cloud-init configures
the network and creates a login account, and the caller gets back the VM ID,
the MAC addresses and — once the guest agent answers — the addresses the guest
actually holds.

The scope is one VM per module instance: everything that describes *this*
machine is an input, and everything that describes the surrounding
infrastructure is not. The module never creates a node, a datastore, a bridge,
a pool or a firewall rule; it references them by name and fails if they are
missing. It also does not clone templates — the boot disk always comes from a
cloud image, either one already sitting in a datastore or one this module
downloads.

## What it does

1. Downloads the cloud image to a datastore when `cloud_image.url` is set, and
   skips straight to step 2 when `cloud_image.file_id` points at an image that
   is already there.
2. Creates the VM on `node_name` with the CPU and memory from `cpu_*` and
   `memory_*`, and the firmware from `bios`, `machine` and `scsi_hardware`.
3. Imports the cloud image onto a boot disk of `disk_size_gb` on
   `datastore_id`, then attaches every entry in `additional_disks` as an empty
   data disk behind it.
4. Attaches one NIC per entry in `network_devices`, in order, each with the
   bridge, MAC and VLAN that entry names.
5. Attaches a cloud-init drive that sets the hostname to `name`, addresses each
   NIC from the same `network_devices` entry, writes the resolver from
   `dns_domain` and `dns_servers`, and creates `username` with
   `ssh_authorized_keys` and `password`.
6. Starts the VM when `started` is true, and waits for the QEMU guest agent to
   report its addresses when `agent_enabled` is true.

## Requirements

| Name | Version |
| --- | --- |
| terraform / opentofu | `>= 1.9.0, < 2.0.0` |
| [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) | `~> 0.114.0` |

The provider is held to a single minor version rather than floating: it is
pre-1.0 and its VM schema moves between minor releases — `network_device` has
already turned from a block into a list attribute, and `enabled` on that
attribute is deprecated — so a floating constraint would break applies without
a commit to blame.

This module declares no `provider` blocks — it inherits the configured instances
from the root module, which is where credentials belong.

### Environment prerequisites

- **A Proxmox VE 8.x endpoint and an API token.** Give its role at least
  `VM.Allocate`, `VM.Audit`, `VM.Config.CDROM`, `VM.Config.CPU`,
  `VM.Config.Cloudinit`, `VM.Config.Disk`, `VM.Config.HWType`,
  `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.Monitor`,
  `VM.PowerMgmt`, `Datastore.Allocate`, `Datastore.AllocateSpace`,
  `Datastore.AllocateTemplate` and `Datastore.Audit` on `/`. Tokens are created
  with privilege separation on, which ignores the user's own permissions — turn
  it off or grant the token its own ACL, or every call comes back 403.
- **A node named by `node_name`,** and a datastore named by `datastore_id` that
  accepts the `images` content type. `local-lvm` does; a plain `local`
  directory datastore does not until you add it.
- **A datastore that accepts `iso`** when `cloud_image.url` is set — that is
  where the download lands. The default is `local`. If you set
  `cloud_image.content_type = "import"` instead, that storage has to have
  `Import` added to its allowed content types under *Datacenter > Storage*
  first: Proxmox enables it nowhere by default.
- **A bridge named by each `network_devices[*].bridge`.** It has to be
  VLAN-aware for `vlan_id` to do anything; on a bridge that is not, the tag is
  accepted and silently dropped.
- **`qemu-guest-agent` inside the image** when `agent_enabled` is true. Without
  it every create and every reboot blocks until `agent_timeout` expires and
  then fails. Most distro cloud images do not ship it — install it through
  cloud-init, bake it into the image, or set `agent_enabled = false`.
- **A datastore with the `snippets` content type** when you pass
  `cloud_init_file_ids`. Proxmox does not enable it anywhere by default.
- **A free VM ID** when `vm_id` is set. Proxmox refuses to reuse one.

## Usage

Both snippets below are excerpts. [examples/](examples) holds the same two
calls as runnable root modules, with the provider configured and the sharp
edges written down:

| Example | What it shows |
| --- | --- |
| [examples/basic](examples/basic) | The smallest call: download an image, take a DHCP lease, take every other default. |
| [examples/static-ip](examples/static-ip) | A fixed VM ID, a pinned MAC, a static address on a tagged VLAN, a separate data disk, and a boot order. |

The first snippet is minimal — every other input takes its default, which
produces a 2-core, 2 GiB, 20 GiB DHCP machine on `vmbr0`.

```hcl
module "vm" {
  source = "./modules/terraform-module-proxmox-linux-vm"

  name      = "web-01"
  node_name = "pve"

  cloud_image = {
    url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    file_name = "debian-12-genericcloud-amd64.img"
  }

  ssh_authorized_keys = [trimspace(file("~/.ssh/id_ed25519.pub"))]
}
```

The second is illustrative rather than a recommendation — the sizes, the
datastore names and the addresses are all placeholders:

```hcl
module "vm" {
  source = "./modules/terraform-module-proxmox-linux-vm"

  name      = "db-01"
  node_name = "pve"
  vm_id     = 9001
  tags      = ["debian", "database"]

  cloud_image = {
    file_id = "local:iso/debian-12-genericcloud-amd64.img"
  }

  cpu_cores    = 4
  memory_mb    = 8192
  datastore_id = "local-lvm"
  disk_size_gb = 40

  additional_disks = [
    { interface = "scsi1", size_gb = 500, datastore_id = "tank", backup = false },
  ]

  network_devices = [
    {
      bridge       = "vmbr0"
      mac_address  = "BC:24:11:00:00:01"
      vlan_id      = 20
      ipv4_address = "192.168.20.10/24"
      ipv4_gateway = "192.168.20.1"
    },
  ]

  dns_domain  = "lan.example"
  dns_servers = ["192.168.20.1"]

  username            = "admin"
  ssh_authorized_keys = [trimspace(file("~/.ssh/id_ed25519.pub"))]

  startup = { order = 10, up_delay = 30 }
}
```

Reaching the machine afterwards, when the address is static:

```console
$ ssh admin@$(tofu output -raw configured_ipv4_address)
```

and when it is not — this needs `agent_enabled`, and the outer index is the
guest interface, so `[1]` is usually the first real NIC after loopback:

```console
$ tofu output -json ipv4_addresses | jq -r '.[1][0]'
```

## Inputs

Only `name`, `node_name` and `cloud_image` are required: they are the three
things the module cannot invent. Everything else defaults to a working
small-VM configuration, and every input that Proxmox itself treats as optional
defaults to `null` so the provider's own default stays in force.

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `name` | Name of this deployment; becomes the VM name and its cloud-init hostname. | `string` | n/a |
| `node_name` | Proxmox VE node the VM is created on. | `string` | n/a |
| `cloud_image` | Source cloud image for the boot disk. See below. | `object` | n/a |
| `vm_id` | Fixed VM ID to claim. Null lets Proxmox allocate the next free ID. | `number` | `null` |
| `migrate` | Live-migrate on a `node_name` change instead of recreating. | `bool` | `false` |
| `description` | Free-text note shown in the Proxmox UI. | `string` | `null` |
| `pool_id` | Existing Proxmox resource pool to place the VM in. | `string` | `null` |
| `tags` | Extra tags applied alongside the tags this module always sets. | `list(string)` | `[]` |
| `cpu_cores` | Cores per socket. | `number` | `2` |
| `cpu_sockets` | Number of CPU sockets; total vCPUs are cores × sockets. | `number` | `1` |
| `cpu_type` | Emulated CPU model. `host` is fastest but constrains live migration. | `string` | `"x86-64-v2-AES"` |
| `memory_mb` | Memory dedicated to the VM, in MiB. | `number` | `2048` |
| `memory_floating_mb` | Ballooning floor in MiB; 0 disables ballooning. | `number` | `0` |
| `datastore_id` | Datastore holding the boot disk, cloud-init drive and EFI disk. | `string` | `"local-lvm"` |
| `disk_size_gb` | Boot disk size in GiB; the image is grown to match on import. | `number` | `20` |
| `disk_interface` | Bus the boot disk attaches to. | `string` | `"scsi0"` |
| `disk_file_format` | Boot disk format. Null takes the datastore default. | `string` | `null` |
| `disk_ssd` | Advertise the boot disk to the guest as an SSD. | `bool` | `true` |
| `disk_discard` | Pass guest TRIM through to the datastore. | `string` | `"on"` |
| `disk_iothread` | Give the boot disk its own I/O thread. | `bool` | `true` |
| `disk_backup` | Include the boot disk in vzdump backups. | `bool` | `true` |
| `additional_disks` | Extra empty data disks attached after the boot disk. See below. | `list(object)` | `[]` |
| `network_devices` | Virtual NICs in order, each with its own addressing. See below. | `list(object)` | `[{}]` |
| `dns_domain` | Search domain written into the guest's resolver. | `string` | `null` |
| `dns_servers` | Nameservers written into the guest's resolver. | `list(string)` | `[]` |
| `username` | Login account cloud-init creates. Null skips account creation. | `string` | `"admin"` |
| `ssh_authorized_keys` | Public keys installed into that account. | `list(string)` | `[]` |
| `password` | Password for that account. **Sensitive.** | `string` | `null` |
| `cloud_init_datastore_id` | Datastore for the cloud-init drive. Null uses `datastore_id`. | `string` | `null` |
| `cloud_init_interface` | Bus the cloud-init drive attaches to. | `string` | `"ide2"` |
| `cloud_init_upgrade` | Run a package upgrade on first boot. Null takes the provider default. | `bool` | `null` |
| `cloud_init_file_ids` | Snippet file IDs overriding the generated config. See below. | `object` | `{}` |
| `agent_enabled` | Tell Proxmox the QEMU guest agent is present. | `bool` | `true` |
| `agent_timeout` | How long to wait for the agent, as a Go duration. | `string` | `"15m"` |
| `started` | Keep the VM running. | `bool` | `true` |
| `on_boot` | Start the VM when the Proxmox node boots. | `bool` | `true` |
| `stop_on_destroy` | Hard-stop on destroy instead of a guest shutdown. | `bool` | `true` |
| `protection` | Set the Proxmox protection flag, which blocks removal. | `bool` | `false` |
| `startup` | Node boot ordering. See below. | `object` | `null` |
| `bios` | `seabios` or `ovmf`; `ovmf` also creates an EFI disk. | `string` | `"seabios"` |
| `machine` | QEMU machine type, e.g. `q35`. Null takes i440fx. | `string` | `null` |
| `scsi_hardware` | SCSI controller model. | `string` | `"virtio-scsi-single"` |
| `os_type` | Guest OS hint; `l26` covers every 2.6+ Linux kernel. | `string` | `"l26"` |
| `boot_order` | Boot device order. Null boots from `disk_interface` alone. | `list(string)` | `null` |
| `serial_device_enabled` | Attach a serial console. | `bool` | `true` |

### `cloud_image`

```hcl
object({
  file_id                 = optional(string)          # image already in a datastore, e.g. "local:iso/debian-12.img"
  url                     = optional(string)          # image to download instead
  datastore_id            = optional(string, "local") # where a downloaded image lands
  content_type            = optional(string, "iso")   # "iso" or "import"
  file_name               = optional(string)          # name to store it under
  checksum                = optional(string)
  checksum_algorithm      = optional(string)          # md5, sha1, sha224, sha256, sha384, sha512
  decompression_algorithm = optional(string)          # gz, lzo, zst, bz2 — for a compressed image
  overwrite               = optional(bool, false)
  upload_timeout          = optional(number)          # seconds; the provider default is 600
})
```

Set exactly one of `file_id` and `url`; validation rejects both and neither.

`file_id` is the path Proxmox uses internally, `datastore:content_type/name` —
`local:iso/debian-12-genericcloud-amd64.img`, not a filesystem path.

**The content type decides how the image reaches the disk,** and the module
picks that for you — from `content_type` when it downloads, and from the file
ID itself when you pass one in:

| Content type | Disk attribute used | Notes |
| --- | --- | --- |
| `iso` (default) | `disk.file_id` | Works on any storage that holds ISOs. Handles compressed images. Changing the image afterwards replaces the VM. |
| `import` | `disk.import_from` | Uncompressed images only, and the storage needs `Import` enabled by hand. Changing the image afterwards is **silently ignored** by the provider. |

`iso` is the default because it is the one that works out of the box.

Proxmox picks the handler for a download from the file name, so a URL ending in
`.qcow2` has to be stored as `.img` under the `iso` content type: set
`file_name` when the URL does not already end in something Proxmox recognises.
Under `import`, `.qcow2` and `.raw` are what it wants, so `file_name` can
usually be left alone.

`checksum_algorithm` is required whenever `checksum` is set. A compressed image
needs `decompression_algorithm` and must use `content_type = "iso"` — the
`import` content type takes uncompressed images only.

### `network_devices`

```hcl
list(object({
  bridge       = optional(string, "vmbr0")
  model        = optional(string, "virtio")
  mac_address  = optional(string)       # null lets Proxmox generate one
  vlan_id      = optional(number)       # 1-4094, on a VLAN-aware bridge
  mtu          = optional(number)
  firewall     = optional(bool, false)  # apply the Proxmox firewall to this NIC
  disconnected = optional(bool, false)
  queues       = optional(number)
  rate_limit   = optional(number)       # MB/s
  trunks       = optional(string)       # semicolon-separated VLAN list

  ipv4_address = optional(string, "dhcp")  # "dhcp", "none", or CIDR
  ipv4_gateway = optional(string)
  ipv6_address = optional(string, "none")  # "dhcp", "auto", "none", or CIDR
  ipv6_gateway = optional(string)
}))
```

Position is meaningful: the first entry becomes `net0` and is configured by the
guest's first interface, the second becomes `net1`, and so on. Reordering the
list renumbers the NICs, which changes their MAC addresses unless you pinned
them.

An address is a **CIDR, not a bare IP** — `192.168.20.10/24`. Proxmox passes
the prefix length straight to cloud-init, and a bare address leaves the guest
with no netmask, so validation rejects it.

Switch an address family off with the string `"none"`, not with `null`:
Terraform reads an explicit `null` on an `optional` attribute that has a
default as "unset" and puts the default back, so `ipv4_address = null` would
quietly mean DHCP. A gateway needs a static address on the same family — DHCP
and SLAAC carry their own.

### `additional_disks`

```hcl
list(object({
  interface    = string                    # "scsi1", "virtio1", ... distinct from every other bus
  size_gb      = number
  datastore_id = optional(string)          # null uses the VM's datastore_id
  file_format  = optional(string)          # null takes the datastore default
  ssd          = optional(bool, false)
  discard      = optional(string, "on")
  iothread     = optional(bool, true)
  backup       = optional(bool, true)
}))
```

These are created empty and unformatted — partitioning and mounting them is the
guest's problem, usually through `cloud_init_file_ids.user_data`. A plan-time
check rejects an `interface` that collides with `disk_interface` or
`cloud_init_interface`, because Proxmox reports no error for that: the second
attachment to a bus replaces the first.

### `cloud_init_file_ids`

```hcl
object({
  user_data    = optional(string)  # e.g. "local:snippets/web-01-user-data.yaml"
  vendor_data  = optional(string)
  meta_data    = optional(string)
  network_data = optional(string)
})
```

Each one replaces the corresponding section that Proxmox would have generated.
Setting `user_data` therefore **overrides `username`, `ssh_authorized_keys` and
`password` entirely** — cloud-init reads the snippet instead. When you do that,
set `username = null` so the module stops asking for a login it no longer
controls, and put your users in the snippet.

Upload the snippet with `proxmox_virtual_environment_file` in the root module
and feed its `id` in here.

### `startup`

```hcl
object({
  order      = optional(number)  # lower starts first
  up_delay   = optional(number)  # seconds to wait before starting the next VM
  down_delay = optional(number)  # seconds to wait before shutting down the next
})
```

Null leaves the VM out of the node's ordered startup sequence entirely, which
is different from giving it a high order.

## Outputs

| Name | Description | Sensitive |
| --- | --- | --- |
| `name` | Name this deployment was created under. | no |
| `tags` | Tags applied to every resource this module creates. | no |
| `vm_id` | Proxmox VM ID, passed in or allocated by the host. | no |
| `node_name` | Proxmox node the VM runs on. | no |
| `username` | Account cloud-init created, or null when creation was skipped. | no |
| `mac_addresses` | MAC of each NIC in net0..netN order, generated ones included. | no |
| `ipv4_addresses` | IPv4 per guest interface, from the guest agent. | no |
| `ipv6_addresses` | IPv6 per guest interface, from the guest agent. | no |
| `network_interface_names` | Interface names inside the guest, from the guest agent. | no |
| `configured_ipv4_address` | First NIC's static IPv4 without its prefix, or null on DHCP. | no |
| `cloud_image_file_id` | File ID the boot disk was imported from. | no |

`configured_ipv4_address` is known at plan time and the agent-reported outputs
are not, so a DNS record or an inventory entry that depends on the latter
forces a second apply. Prefer static addressing when something downstream needs
the address during the same run.

No output is marked sensitive, but `password` is: it is stored in state in
plain text, as are the public keys. Use a backend that encrypts state.

## Resources created

| Address | Purpose |
| --- | --- |
| `proxmox_download_file.cloud_image[0]` | The cloud image, fetched onto the node. Only created when `cloud_image.url` is set. |
| `proxmox_virtual_environment_vm.this` | The VM, its disks, its NICs and its cloud-init drive. |

## Baked-in decisions

- **The boot disk is imported from an image, never cloned from a template.** A
  template clone is faster and it is what most Proxmox modules do, but it makes
  the module's output depend on a mutable object in the cluster that Terraform
  did not create. Importing from an image with a checksum makes the same
  configuration produce the same machine on any node.
- **Account creation goes through Proxmox's cloud-init fields, not a generated
  snippet.** A snippet would be more expressive, but it needs a datastore with
  the `snippets` content type enabled, which no Proxmox install has by default.
  `cloud_init_file_ids` is the way out when you need the expressiveness.
- **The EFI disk is `4m` with `pre_enrolled_keys = false`.** Enrolling
  Microsoft's keys turns on Secure Boot, and distro cloud images are a coin
  flip on whether they are signed for it. Off boots; on sometimes does not.
- **`network_device.enabled` is not exposed.** It is deprecated upstream and
  warns on every plan that sets it. Remove the entry from `network_devices`
  instead, or set `disconnected = true` to keep the NIC but unplug the cable.
- **Tags always include `opentofu` and the deployment name.** They are what
  makes a VM findable in the Proxmox UI as something Terraform owns.
- **No CD-ROM drive.** The cloud-init drive is the only removable media, which
  keeps `boot_order` unambiguous.

## Lifecycle notes

- **Changing `cloud_image` either replaces the VM or does nothing at all,
  depending on the content type.** Under `iso` the image arrives through
  `disk.file_id`, which the provider marks as forcing replacement: the VM and
  its disks are destroyed and rebuilt. Under `import` it arrives through
  `disk.import_from`, which the provider reads *only when the VM is created*
  and ignores on every update — the plan is clean, the apply does nothing, and
  the VM keeps running the old image. Either way, re-imaging an existing VM
  means `-replace`, not an edit.
- **Changing `vm_id` replaces the VM,** and so does changing `node_name` unless
  `migrate = true`. The disks go with it. Anything stored only on those disks
  is gone — this is the change to look for in a plan.
- **Changing any `cloud_init_file_ids` entry replaces the VM.** The provider
  marks all four snippet IDs as forcing replacement, so pointing `user_data` at
  a new snippet is a rebuild. Editing the snippet's *contents* under the same
  file ID is not — and is also not picked up by a running guest, since
  cloud-init has already run.
- **`disk_size_gb` grows in place and never shrinks.** Proxmox rejects a
  shrink, and the apply fails after the plan showed an in-place update. Growing
  the disk does not grow the filesystem; the image's `growpart` does that on
  the next boot.
- **Most cloud-init changes reboot the VM.** The provider's
  `reboot_after_update` defaults to true, so editing an address, the DNS
  servers or the SSH keys regenerates the cloud-init drive and bounces the
  guest during `apply`. Plan those changes into a window.
- **Moving a disk between datastores is a move, not a rebuild.** Changing
  `datastore_id`, or an `additional_disks` entry's, makes the provider issue a
  disk move. It is safe, and on a large disk it is slow enough to outlast a
  default apply timeout.
- **Editing `username`, `password` or `ssh_authorized_keys` does not reliably
  reach an existing guest.** Most images run the user module once, on first
  boot, and skip it forever after — the drive gets the new values and the guest
  ignores them. Rotate keys through configuration management, or recreate the
  VM.
- **`agent_enabled = true` against an image without the agent hangs the
  apply.** It waits `agent_timeout` — 15 minutes by default — on create and on
  every reboot, then fails. If an apply is stuck at "still creating" with no
  error, this is why.
- **`protection = true` makes `destroy` fail.** Clearing it is its own apply,
  which has to finish before the destroy can start. That is the point of the
  flag, but it means a teardown is two steps.
- **A downloaded image is not re-fetched when its URL changes.** With
  `overwrite = false` the provider adopts whatever is already stored under that
  `file_name`. Point `file_name` at a new name — include the release, not
  `latest` — or set `overwrite = true` and accept that the VM is replaced.
- **Removing an entry from the middle of `network_devices` renumbers the ones
  after it.** `net2` becomes `net1`, takes `net1`'s MAC, and the guest's
  interface names may shift with it. Static DHCP reservations break. Pin
  `mac_address` on anything that matters.
- **The module does not free the VM ID on destroy any faster than Proxmox
  does.** Re-applying immediately with the same `vm_id` can collide with a
  half-finished removal; wait for the node's task list to clear.

## Layout

| File | Contents |
| --- | --- |
| [variables.tf](variables.tf) | Inputs and single-variable validation. |
| [main.tf](main.tf) | Locals, the two resources, and the cross-variable preconditions. |
| [outputs.tf](outputs.tf) | The module's contract. |
| [versions.tf](versions.tf) | Terraform and provider constraints. |
| [tests/validation.tftest.hcl](tests/validation.tftest.hcl) | One run block per input the module must reject. |
| [tests/vm.tftest.hcl](tests/vm.tftest.hcl) | What the module sends to the provider, and the values it hands back. |
| [examples/basic](examples/basic) | A runnable root module calling this one with almost nothing set. |
| [examples/static-ip](examples/static-ip) | The same, with the addressing, sizing and disks a real machine needs. |

## Development

Commits on `main` follow [Conventional
Commits](https://www.conventionalcommits.org/en/v1.0.0/): the subject prefix
decides the CHANGELOG section and the version bump. `feat:` and `fix:` are the
ones that produce a release; `chore:`, `style:` and `test:` are hidden from the
changelog.

- **Validate** (`.github/workflows/terraform-validate.yml`) runs on every pull
  request: `terraform fmt -check`, then `terraform validate`, `terraform test`
  and a validate of every directory under `examples/`, against both the version
  floor from [versions.tf](versions.tf) and the current release — all of it
  again under OpenTofu — plus `tflint` with [.tflint.hcl](.tflint.hcl). Run the
  same checks locally:

  ```console
  $ terraform fmt -recursive
  $ terraform init -backend=false && terraform validate
  $ terraform test
  $ terraform -chdir=examples/basic init -backend=false && terraform -chdir=examples/basic validate
  $ tflint --init && tflint -f compact --recursive
  ```

  `validate` type-checks against the provider schema without credentials, which
  catches a schema drift after a provider bump. It cannot catch a wrong
  datastore name or a missing bridge — only an apply does.

  `terraform test` needs no Proxmox node and no API token: both test files
  declare `mock_provider "proxmox" {}`. What they cover is every input the
  validation must reject, both preconditions, the defaults a three-input call
  gets, the routing of an image onto the boot disk, and the ordering of NICs
  against their addresses. What they cannot cover is anything a node decides —
  an allocated `vm_id`, the agent-reported addresses, a generated MAC — because
  the mock invents those values, so none of it is asserted.

  Two details in those files are load-bearing. `mock_resource` pins the
  download's `id` to a real-looking Proxmox file ID, because OpenTofu generates
  computed values eagerly and the provider's own validator rejects the random
  string it would otherwise produce. And one run uses `command = apply` rather
  than `plan`, because the boot disk is built from that computed `id` and a
  plan leaves it unknown — against a mocked provider the apply reaches no node.

  `examples/` is validated but never planned: `bpg/proxmox` does not contact
  the node when it is configured, only when a resource is read or created, so a
  plan there would reach a real API.

- **Release** (`.github/workflows/release.yml`) runs
  [release-please](https://github.com/googleapis/release-please) on `main`. It
  keeps a release PR open that accumulates `CHANGELOG.md` entries; merging that
  PR writes the changelog, bumps
  [.release-please-manifest.json](.release-please-manifest.json) and tags the
  release as `v<version>`. While the major version is `0`,
  `bump-minor-pre-major` turns a breaking change into a minor bump rather than
  `1.0.0`.

Bumping `bpg/proxmox` is a `deps:` commit, and it needs a read of the
provider's changelog rather than just a green `validate`: the schema changes
that hurt are the ones that still type-check.
