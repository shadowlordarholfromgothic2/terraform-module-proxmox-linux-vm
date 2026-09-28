# cloud-init snippet example

The module rendering its own cloud-config and uploading it as a Proxmox snippet,
instead of leaving the user-data to Proxmox. That buys the three things Proxmox's
own cloud-init fields cannot do at all: install packages, run commands, and write
files on first boot.

The first of those is not a nicety. Proxmox's fields create an account and
configure the network, and stop there — so on a stock cloud image, which does not
ship `qemu-guest-agent`, `agent_enabled = true` waits out `agent_timeout` (15
minutes) for an agent that will never answer and then fails the apply, on a VM
that is up and running the whole time. Installing the agent needs a real
cloud-config, which is what this is.

```console
$ export TF_VAR_proxmox_api_token='terraform@pve!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$ export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
$ export TF_VAR_admin_password_hash="$(mkpasswd -m sha512crypt)"   # optional
$ tofu init
$ tofu plan
$ tofu apply
$ ssh admin@<the address the agent reports>
```

## Two things to set up on the node first

Unlike the other examples, this one does not run against an untouched Proxmox
install.

1. **The `snippets` content type**, on whichever datastore
   `snippet_datastore_id` names. Proxmox enables it nowhere by default:
   *Datacenter > Storage > (the datastore) > Edit > Content*, then tick
   *Snippets*. Without it the upload fails with a storage error that does not
   mention snippets.
2. **SSH to the node**, which is why this example's provider block has an `ssh`
   block and the others do not. Snippets are the one content type the Proxmox API
   refuses an upload for, so the provider writes them over SFTP. `agent = true`
   takes the key from the running `ssh-agent`; if there is no agent where this
   runs — CI, most often — use `private_key` instead. The user needs write access
   to the datastore's snippets directory, which in practice means `root`.

The API token still does everything else. SSH is *additional* here, not a
replacement.

## What this example is showing

| Input | Why it is here |
| --- | --- |
| `cloud_init_snippet.install_qemu_guest_agent` | On by default whenever the snippet is. The one line that makes `agent_enabled = true` work on a stock image. |
| `cloud_init_snippet.packages` / `.runcmd` | Install something and start it. `runcmd` runs in cloud-init's final stage, after the package module, so the unit exists by then. |
| `cloud_init_snippet.write_files` | Drop a config file in place before the service that reads it starts. `permissions` is a quoted octal string — YAML reads an unquoted `644` as decimal. |
| `cloud_init_snippet.ssh_pwauth` | Ubuntu and Debian cloud images ship `PasswordAuthentication no`, so a password is a console login until this is true. |
| `cloud_init_snippet.extra_yaml` | Top-level cloud-config keys the object does not model. Appended, so a key repeated here is a duplicate, not an override. |
| `password` as a hash | Passed through to `hashed_passwd` byte for byte. Proxmox's `cipassword` hashes what it is handed unless it recognises the prefix, and it does not recognise `$y$` yescrypt. |
| `serial_device_enabled` | When cloud-init fails before the network comes up, `qm terminal <vmid>` on the node is what shows why. |

## What the snippet has to restate, and what it does not

Proxmox splits the config it generates across user-data and network-data, and a
snippet replaces **only the user-data**. So the module writes `hostname`, `fqdn`
(from `dns_domain`) and `manage_etc_hosts` into the snippet itself, because those
came from the file being replaced.

The address and the resolver are not restated, and must not be: they live in the
network-data, which Proxmox still generates from `network_devices`, `dns_domain`
and `dns_servers`. That is why this example sets no addresses in the snippet and
still gets a configured NIC.

## When it goes wrong

The snippet is a file on the node, so it can be read back:

```console
$ cat /var/lib/vz/snippets/web-01-user-data.yaml   # what was uploaded
$ qm cloudinit dump <vmid> user                    # what cloud-init was handed
$ qm terminal <vmid>                               # what cloud-init did with it
```

Inside the guest, `cloud-init status --long` and
`/var/log/cloud-init-output.log` are the next two places to look. An empty
`ipv4_addresses` output after a successful apply means the agent never started —
check that the package install had a route to its mirrors.

Editing the snippet after the VM exists re-uploads the file but does **not**
reconfigure the guest: cloud-init has already run. A snippet change that has to
take effect needs `tofu apply -replace=module.vm.proxmox_virtual_environment_vm.this`.
