# Basic example

One Debian VM on DHCP, the smallest complete call of this module: a configured
`proxmox` provider, an image to build from, and a key to get in with.
Everything else is left at its default — 2 cores, 2048 MiB, a 20 GiB boot disk
on `local-lvm`, and one virtio NIC on `vmbr0`.

The image is downloaded to the node on the first apply and reused afterwards.
The URL here points at Debian's `latest` symlink, which is convenient and not
reproducible: what decides whether the image is re-fetched is the *file name*,
so pin a release in both before this stops being an example.

```console
$ export TF_VAR_proxmox_api_token='terraform@pve!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$ tofu init
$ tofu plan
```

Unlike a provider that dials out when it is configured, `bpg/proxmox` does not
contact the node until a resource is read or created — so `tofu plan` here
reaches the API, but `tofu validate` does not. CI therefore validates this
directory and never plans it. To exercise the module itself without a Proxmox
node at all, use the tests in [../../tests](../../tests), which mock the
provider.

Every input has a default except `proxmox_api_token`, so a run against a node
at `192.168.1.10` named `pve` needs only that one variable. The defaults are
placeholders for a home network — check `proxmox_endpoint`, `proxmox_node` and
the `vmbr0` bridge against your own before applying.

## Two things that will bite

**`agent_enabled = false` is deliberate.** Debian's generic cloud image does
not ship `qemu-guest-agent`, and with the agent declared enabled the provider
waits for it on create and on every reboot — fifteen minutes, then a failure.
Once the image has an agent, turn this on and `ipv4_addresses` starts
reporting.

**The address is a DHCP lease, so nothing here knows it at plan time.** The
`mac_addresses` output is the useful one: point a reservation at it, or read
the address back from `ipv4_addresses` on a second apply once the guest agent
is answering. When something downstream needs the address during the same run,
assign it statically instead — see [../static-ip](../static-ip).
