# Static addressing example

The same module doing the things a real machine needs: a fixed VM ID, a pinned
MAC, a static address on a tagged VLAN, sized CPU and memory, a separate data
disk, and a place in the node's boot order.

It builds from an image that is **already in a datastore** rather than
downloading one, which is what you want once more than one VM shares an image.
Download it once — by hand, or by running [../basic](../basic) — and point
`cloud_image_file_id` at it.

```console
$ export TF_VAR_proxmox_api_token='terraform@pve!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$ tofu init
$ tofu plan
$ tofu apply
$ ssh admin@192.168.20.10
```

The addresses, the VLAN and the datastore names are placeholders. Replace them
before running this anywhere real: creating a VM on an address something else
already holds is not a harmless mistake.

## What this example is showing

**The address is known at plan time.** Because it is assigned rather than
leased, `tofu plan` can already print the `ssh_command` output — so a DNS
record, a firewall rule or an Ansible inventory built in the same run can
depend on it. With DHCP that takes a second apply, after the guest agent has
reported in.

**The MAC is pinned on purpose.** Proxmox generates one per NIC and keeps it
for the life of the VM, but a rebuild gets a new one. Anything keyed to the MAC
— a DHCP reservation, a switch port rule, a licence — breaks silently at that
point. Fixing it in configuration costs one line.

**`ipv4_address` is a CIDR, not a bare IP.** The prefix length is handed
straight to cloud-init; without it the guest comes up with no netmask. The
module rejects a bare address rather than letting that reach the node.

**The data disk is separate from the boot disk,** on its own datastore and out
of the backup set. It arrives empty and unformatted — partitioning and mounting
it is the guest's job, usually through a cloud-init snippet.

**`agent_enabled = true` assumes the image has one.** If yours does not, this
apply hangs for `agent_timeout` and then fails. Either bake
`qemu-guest-agent` into the image, install it from a cloud-init snippet, or
set this to `false` as [../basic](../basic) does.
