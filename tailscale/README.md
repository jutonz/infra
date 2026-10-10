# Offsite access

crents is an Ubuntu 26.04 mini PC. It will live at a friend's house with
no inbound ports. Later, it will run a standalone k3s cluster and hold
restic append-only backups. Those two jobs are not yet set up, and this
document does not cover them. The 8 TB WD Red disk at `/dev/sda` is not
yet in use.

Two independent paths reach the sshd on crents. If one path fails, use
the other path.

1. **Tailscale path.** crents joins the tailnet as `tag:offsite`. The
   policy in `policy.hujson` lets members and `tag:home` nodes reach it.
   crents can reach nothing.
2. **Reverse tunnel.** autossh on crents dials
   `tunnel.jutonz.com:22022`. The router forwards that port to the
   keepalived VIP `192.168.1.21`, so cary or mini answers. sshd on the
   VIP holder then listens on `192.168.1.21:2222` and forwards to port 22
   on crents.

## Hosts

| Host      | Role                          | Tailscale tag | Tailscale IP      |
| --------- | ----------------------------- | ------------- | ----------------- |
| crents    | Offsite box                   | `tag:offsite` | `100.72.21.85`    |
| cary      | k3s node, tunnel endpoint     | `tag:home`    | `100.110.173.115` |
| mini      | k3s node, tunnel endpoint     | `tag:home`    | `100.127.17.103`  |
| littlebox | k3s node                      | `tag:home`    | `100.90.96.99`    |

The crents host key is ED25519
`SHA256:4kRusAE6YTBkzXmpCSWRznzsQXc0i4ew5DiUzy0v7dY`. Compare it on the
first connection after a rebuild or a new laptop.

## Tailscale path

* The tailnet is `tail98377b.ts.net`, on the free plan. The owner signs
  in with GitHub as `jutonz@github`.
* Only the ansible OAuth client holds `tag:ansible`. No node has it.
* Every node runs with `--accept-dns=false` and `--accept-routes=false`.
  Tailscale SSH is off. Auto-update is on.
* The tailnet has no exit nodes and no subnet routes.
* Tagged nodes have no key expiry.

The policy grants these connections. Tailscale denies all others.

| Source             | Destination   | Ports          |
| ------------------ | ------------- | -------------- |
| `autogroup:member` | `tag:offsite` | 22             |
| `tag:home`         | `tag:offsite` | 22, 9100       |

No grant has `tag:offsite` as its source, so crents cannot start a
connection into the tailnet. Members cannot reach `tag:home`. This is on
purpose. When you are away, connect to the home VPN to reach home hosts.

Every k3s node must be on the tailnet. Prometheus runs as a Deployment
with no node pin, so it can run on any node. Flannel masquerades pod
traffic to the tailnet IP of the node, so pods reach `100.x` addresses
only through a node that is on the tailnet.

## Reverse tunnel

| Part              | Value                                              |
| ----------------- | -------------------------------------------------- |
| Client unit       | `reverse-tunnel` systemd unit on crents            |
| Client user       | `tunnel` (no shell)                                |
| Dial target       | `tunnel.jutonz.com:22022`                          |
| DNS               | `tunnel.jutonz.com` CNAME `jutonz.com`, in DigitalOcean |
| Home IP           | `50.89.198.143`                                    |
| Router forward    | WAN TCP 22022 → `192.168.1.21:22022`               |
| Tunnel endpoint   | VIP holder, cary or mini (`ansible/haproxy-k3s-vip`) |
| Listen address    | `192.168.1.21:2222` on the VIP holder              |

The home IP has not changed so far. A DDNS CronJob is a separate future
ticket and is not yet set up. If the home IP changes, the tunnel fails
until you update DNS.

sshd on cary and mini listens on ports 22 and 22022. The
`Match LocalPort 22022` block in
`ansible/reverse-tunnel/files/60-reverse-tunnel.conf.j2` sets these
limits:

* Only the `tunnel` user can log in.
* The user can only forward ports. It gets no shell and no TTY.
* The user can listen only on `192.168.1.21:2222`.
* sshd drops a dead session after about 45 s
  (`ClientAliveInterval 15`, `ClientAliveCountMax 3`).

Only the home LAN and the home VPN can reach `192.168.1.21:2222`.

When the VIP moves, the tunnel moves to the new holder by itself. This
took about 30 s in a test. cary and mini have equal VRRP priority, so the
VIP does not move back when the other node returns.

From the home LAN, crents dials the public IP and the router hairpins the
connection. The endpoint then sees the session come from `192.168.1.1`.

## Get in

The owner's `~/.ssh/config` has these entries:

```
Host crents
  HostName crents.tail98377b.ts.net
Host crents-tunnel
  HostName 192.168.1.21
  Port 2222
Host crents crents-tunnel
  User jutonz
  HostKeyAlias crents
  IdentityFile ~/.ssh/crents-jutonz.pub
  IdentityFile ~/.ssh/crents-root.pub
  IdentitiesOnly yes
```

```sh
# Tailscale path, from any tailnet device
ssh crents
ssh root@crents

# Reverse tunnel, from the home LAN or the home VPN
ssh crents-tunnel
ssh -p 2222 root@192.168.1.21
```

Both entries use `HostKeyAlias crents`, so one `known_hosts` entry
covers both paths.

The playbooks in `ansible/` use the host name `crents`, so they use the
Tailscale path.

## Credentials

All credentials are in the 1Password `Infra` vault, item `Tailscale`.
This document records only where they are.

| Field                     | Client   | Scope                       |
| ------------------------- | -------- | --------------------------- |
| `TS_OAUTH_ID`             | gitops   | Policy file: write          |
| `TS_OAUTH_SECRET`         | gitops   | Policy file: write          |
| `TS_TAILNET`              | gitops   | Tailnet name                |
| `ansible oauth client id` | ansible  | Auth keys: write, `tag:ansible` |
| `ansible oauth secret`    | ansible  | Auth keys: write, `tag:ansible` |

The tunnel client key is on crents at `/var/lib/tunnel/.ssh/id_ed25519`.
The reverse-tunnel playbook makes it and copies the public key to the
endpoints.

To rotate an OAuth client:

1. In the admin console, go to Settings → OAuth clients. Create a new
   client with the same scope and tags.
2. Put the new ID and secret in the 1Password item.
3. If the client is gitops, update the GitHub Actions secrets too.
4. Revoke the old client.

## Policy changes

`.github/workflows/tailscale-policy.yml` runs when `policy.hujson`
changes:

* On a pull request, it tests the policy.
* On a push to main, it applies the policy.

The workflow needs the GitHub Actions secrets `TS_OAUTH_ID`,
`TS_OAUTH_SECRET`, and `TS_TAILNET`. These secrets are not yet set up.
Until they are, apply each change by hand:

1. Edit `policy.hujson` and merge it.
2. Paste the file into the JSON editor under Access controls in the admin
   console.

The next apply from the workflow overwrites edits made in the console.
Always edit `policy.hujson` first.

## Monitoring

The blackbox exporter runs in the `monitoring` namespace. Its
`ssh_banner` module opens a TCP connection and expects `SSH-2.0-`.

The Prometheus config is in `monitoring/prometheus-config-secret.yaml`.
sops encrypts that file, so edit it only with `sops edit`.

| Job                    | Target               | Label                 |
| ---------------------- | -------------------- | --------------------- |
| `crents_node_exporter` | `100.72.21.85:9100`  |                       |
| `crents_ssh`           | `100.72.21.85:22`    | `path=tailscale`      |
| `crents_ssh`           | `192.168.1.21:2222`  | `path=reverse-tunnel` |

Prometheus mounts its config with `subPath`, so it does not see changes
by itself. Restart it after each config change:

```sh
kubectl -n monitoring rollout restart deploy/prometheus
```

crents cannot reach the Pushgateway, because it opens no connections
home. Its apt metrics and its `node_reboot_required` metric go to
`/var/lib/node_exporter/textfile`. Prometheus scrapes them over the
tailnet with the other node_exporter metrics.

### Alerts

Grafana alerts for crents are not yet set up. Make them in the Grafana
UI. These are the planned rules:

| Alert                   | Query                                                  | For |
| ----------------------- | ------------------------------------------------------ | --- |
| Tailscale path down     | `probe_success{job="crents_ssh",path="tailscale"} == 0`      | 10m |
| Reverse tunnel down     | `probe_success{job="crents_ssh",path="reverse-tunnel"} == 0` | 10m |
| crents needs reboot     | `node_reboot_required{job="crents_node_exporter"} == 1`      | 1h  |

## Operations

### Run the playbooks

Run them in this order. Each `update.sh` reads secrets through the
1Password CLI, which asks you to approve.

```sh
cd ansible/tailscale && ./update.sh
cd ../reverse-tunnel && ./update.sh
cd ../node_exporter && ./update.sh
```

The reverse-tunnel playbook changes cary, mini, and crents together. Do
not limit it to one host, because the endpoints need the current client
key from crents.

`ansible/update` also includes crents, for manual package upgrades.

### Reboot crents

unattended-upgrades is on, but it does not reboot the box. Reboot by
hand when `node_reboot_required` is 1.

```sh
ssh root@crents reboot
```

Then check that both paths come back:

```sh
ssh crents true
ssh crents-tunnel true
```

### Rebuild crents

Use this procedure after a fresh OS install. Do it at home if you can.

1. Install Ubuntu. Add the SSH public keys for `jutonz` and `root`. No
   playbook in this repo does this step.
2. In the BIOS, set the box to power on after AC loss.
3. In the Tailscale admin console, remove the old crents node. If you do
   not, Tailscale gives the new node a different name.
4. Remove the old host key from your laptop:

   ```sh
   ssh-keygen -R crents
   ```

5. Run the tailscale playbook. crents is not yet on the tailnet, so point
   Ansible at its LAN address:

   ```sh
   cd ansible/tailscale
   ansible-playbook -i ./hosts.yaml ./playbook.yaml -l crents -e ansible_host=<LAN IP>
   ```

6. Connect with `ssh crents`. Record the new host key fingerprint in the
   Hosts section of this document.
7. Run the reverse-tunnel playbook, then the node_exporter playbook, as
   in "Run the playbooks".
8. If the Tailscale IP changed, update the Hosts table and the
   Prometheus targets.
9. Run the acceptance checklist.

At the friend's house, the friend only plugs in Ethernet and power, then
turns the box on. A smart plug for remote power cycles is planned but not
yet set up.

### Test on a phone hotspot

Use a hotspot to test the box on a network that is not the home LAN. The
Wi-Fi card is `wlp4s0` (MediaTek MT7921). On an iPhone, turn on
Maximize Compatibility.

1. Make `/etc/netplan/90-hotspot.yaml`:

   ```yaml
   network:
     version: 2
     wifis:
       wlp4s0:
         dhcp4: true
         access-points:
           "<SSID>":
             password: "<password>"
   ```

2. Apply it, then unplug Ethernet:

   ```sh
   chmod 600 /etc/netplan/90-hotspot.yaml
   netplan apply
   ```

3. Before the box leaves the house, remove the hotspot config:

   ```sh
   rm /etc/netplan/90-hotspot.yaml
   netplan apply
   ```

## Acceptance checklist

Run this list again after big changes.

| Check          | How                                                     | Last result                       |
| -------------- | ------------------------------------------------------- | --------------------------------- |
| Tailscale SSH  | `ssh crents true`                                       | Works. Direct, not relayed, over cellular CGNAT. |
| Tunnel SSH     | `ssh crents-tunnel true`                                | Works over cellular.              |
| VIP failover   | Stop keepalived on the VIP holder, then retry the tunnel | Tunnel came back in about 30 s.  |
| Reboot         | `ssh root@crents systemctl reboot`, then retry both paths | Both paths came back in about 45 s. |
| Power pull     | Pull the power, plug it in, then retry both paths       | Booted by itself. Both paths came back in about 2 min. |
| Alerts fire    | Break each path and wait for the alert                  | Alerts not yet set up.            |

A VIP failover test also moves the public sites, so they blip. Start
keepalived again after the test.

To find the VIP holder, run this on cary and on mini:

```sh
ip -br addr | grep 192.168.1.21
```

## Troubleshooting

### `tailscale up` says the tags are not permitted

* **Symptom:** The join fails with
  `requested tags [tag:X] are invalid or not permitted`.
* **Cause:** An OAuth client with several tags can mint only keys that
  carry all of those tags.
  [tailscale/terraform-provider-tailscale#437](https://github.com/tailscale/terraform-provider-tailscale/issues/437)
* **Fix:** Give the ansible client the single tag `tag:ansible`. In
  `tagOwners`, `tag:ansible` owns `tag:home` and `tag:offsite`.

The join task uses `no_log`, so Ansible hides its output. The playbook
prints the error in a later task, with the key redacted.

### The tunnel does not come back after crents changes networks

* **Symptom:** `journalctl -u reverse-tunnel` on crents shows
  `remote port forwarding failed for listen port 2222`. SSH clients hang
  at "banner exchange".
* **Cause:** A dead session on the endpoint still holds
  `192.168.1.21:2222`.
* **Fix:** The Match block sets `ClientAliveInterval 15` and
  `ClientAliveCountMax 3`, so sshd drops a dead session in about 45 s.
  Wait, then check the log again.

A session keeps the config that it started with. After a change to the
sshd config, an old session can still hold the port. Find it on the VIP
holder and kill it by hand:

```sh
ss -tnp state established '( sport = :22022 )'
kill <pid>
```

### sshd ignores a port change on the endpoints

* **Symptom:** sshd does not listen on a new port after a config change.
* **Cause:** Ubuntu uses socket activation for sshd. `ssh.socket` reads
  the ports only when the systemd generator runs again.
* **Fix:** Run `systemctl daemon-reload`, then restart `ssh.socket`. The
  playbook handler does this.

### The tunnel session comes from `192.168.1.1`

* **Symptom:** On the endpoint, the tunnel session comes from
  `192.168.1.1`, not from a public IP.
* **Cause:** crents is on the home LAN. It dials the public IP, and the
  router hairpins the connection.
* **Fix:** None. This is normal at home.

### Prometheus cannot scrape crents

* **Symptom:** The `crents_node_exporter` or `crents_ssh` targets are
  down, but `ssh crents` works.
* **Cause:** The Prometheus pod runs on a node that is not on the
  tailnet.
* **Fix:** Run the tailscale playbook so every k3s node joins the
  tailnet.

### crents has no apt or reboot metrics

* **Symptom:** `node_reboot_required` for crents is missing.
* **Cause:** crents cannot reach the Pushgateway.
* **Fix:** Look for the metrics in the `crents_node_exporter` job, not in
  the Pushgateway. The files are in `/var/lib/node_exporter/textfile` on
  crents.

## Bootstrap

These steps set up the tailnet and the tunnel for the first time. They
are done. Use them again only to start from zero.

1. Create the tailnet: sign in at https://login.tailscale.com with
   GitHub.
2. Paste `policy.hujson` into the admin console's JSON editor. The tags
   must exist before an OAuth client can own them.
3. Create two OAuth clients under Settings → OAuth clients:
   * `gitops`, scope **Policy file: write**. Store the ID, the secret,
     and the tailnet name in the 1Password item `Tailscale`. Also set
     them as GitHub Actions secrets. This step is not yet done.
   * `ansible`, scope **Auth keys: write**, tag `tag:ansible` only.
     Store the ID and the secret in the same item.
4. In DigitalOcean DNS, add `tunnel.jutonz.com` as a CNAME to
   `jutonz.com`.
5. On the router, forward WAN TCP 22022 to `192.168.1.21:22022`.
6. Run the playbooks, as in "Run the playbooks".
7. In the admin console, check that key expiry is off for crents. Tagged
   nodes have it off by default.
