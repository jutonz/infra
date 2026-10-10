# Homelab

The services and machines that this repository deploys and backs up.

## Notes sync

**Vault**:
The one set of Obsidian notes that all devices share.
_Avoid_: notes repo, notebook

**Device**:
An Obsidian install that syncs the Vault, such as a Mac, an iPhone, or the iPad.
_Avoid_: client, peer

**Remote**:
The encrypted CouchDB database `notes` that every device syncs through.
_Avoid_: server, CouchDB, LiveSync server

**Vault Mirror**:
A decrypted copy of the Vault in the cluster, kept current from the Remote so that it can be backed up. It is not a device: nobody edits it.
_Avoid_: server sync, headless vault

**Backup**:
The git history of the Vault in `jutonz/notes` on littlebox. Changes flow from the Vault Mirror into the Backup, never back.
_Avoid_: sync, git sync

**Setup URI**:
An encrypted link that holds everything a new device needs to join the Remote, including the end-to-end encryption passphrase and the ID key.

**Rebuild**:
The deletion and re-upload of the whole Remote from one device.
_Avoid_: overwrite remote, reset

**Remote Lock**:
The state of the Remote after a Rebuild, in which each other device and the Vault Mirror must be accepted again before it can sync.

## Offsite access

**Offsite box**:
crents, the mini PC at a friend's house. It accepts no inbound connections and opens none into the tailnet. See `tailscale/README.md`.
_Avoid_: remote, offsite server

**Tailscale path**:
The SSH route to the Offsite box over the tailnet, at `crents.tail98377b.ts.net`.

**Reverse tunnel**:
The SSH route that the Offsite box opens to home with autossh. It reaches the Offsite box at `192.168.1.21:2222` from the home LAN or the home VPN.
_Avoid_: VPN, backdoor

**Tunnel endpoint**:
The host that holds the keepalived VIP `192.168.1.21`, cary or mini. Its sshd accepts the Reverse tunnel on port 22022.

**Tunnel user**:
The `tunnel` account on the Offsite box and on each Tunnel endpoint. It can only forward one port and has no shell.
