# LiveSync

Syncs the Obsidian Vault between devices in near real time, and backs it up
to git. Terms such as Remote, Vault Mirror, and Rebuild are defined in
[CONTEXT.md](../CONTEXT.md).

```
 Devices                     namespace: livesync                         littlebox
 ┌──────────┐            ┌────────────┐     ┌─────────────────────┐     ┌────────────┐
 │ Macs     │◄──────────►│ Remote     │────►│ Vault Mirror        │     │ jutonz/    │
 │ iPhones  │ LiveSync,  │ (CouchDB,  │     │  livesync-cli:      │     │ notes.git  │
 │ iPad     │ encrypted  │ encrypted) │     │   decrypts to .md   │     │ (Backup)   │
 └──────────┘            └────────────┘     │  git-backup:        │────►│            │
                                            │   commits every 15m │     └────────────┘
                                            └─────────────────────┘
```

- **Remote:** `https://livesync.home.jutonz.com`, database `notes`. It is
  reachable from the home network only. Away from home, connect the VPN
  first.
- **Vault Mirror:** the `vault-sync` Deployment. The `livesync-cli`
  container writes the Vault to `/data/vault`, and the `git-backup` container
  commits and pushes it. Each successful run sets
  `last_success_timestamp_seconds{job="livesync_git_backup"}` in the
  pushgateway.
- **Backup:** `git@littlebox:jutonz/notes.git`. restic backs up littlebox's
  `/home/git` twice a day, and Longhorn backs up the CouchDB volume to S3
  daily.

## Design choices

- **LiveSync syncs; git only backs up.** Nothing flows from git back into the
  Vault. To edit notes, use Obsidian on a device.
- **The Vault Mirror is the official LiveSync CLI**, not livesync-bridge. The
  bridge cannot read vaults that use the ID key that plugin 1.0.33 added.
- **The Vault Mirror skips dot-paths.** `.obsidian/` is not in the Backup.
  Device settings sync through LiveSync's customization sync instead.
- **Devices log in as `livesync`, which is not an admin.** A leaked device or
  Setup URI cannot delete databases or change the server. The cost is that a
  Rebuild needs the admin login for a short time (see below).

## Secrets

| Secret | 1Password (Infra → "Obsidian LiveSync") | SOPS |
|---|---|---|
| `livesync` password | `password` | `secret-couchdb.yaml` |
| E2EE passphrase | `e2ee passphrase` | (inside the Setup URI) |
| Setup URI | `setup uri` | `secret-vault-sync.yaml` |
| Setup URI passphrase | `setup uri passphrase` | `secret-vault-sync.yaml` |
| CouchDB admin | `couchdb admin` section | `secret-couchdb.yaml` |
| `livesync-server` password | | `secret-couchdb.yaml` |
| Git deploy key | | `secret-vault-sync.yaml` |

`.envrc` exports the `password`, `setup uri`, and `setup uri passphrase`
fields. To copy a changed value into SOPS:

```sh
sops set livesync/secret-vault-sync.yaml '["stringData"]["setup-uri"]' \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$LIVESYNC_SETUP_URI")"
```

The deploy key on littlebox is restricted to `git-shell` in
`/home/git/.ssh/authorized_keys`.

## Add a device

1. Install the **Self-hosted LiveSync** plugin in Obsidian.
2. Open an **empty** vault folder. Do not add a device that already has notes,
   or LiveSync merges the two copies.
3. Choose to set up from a Setup URI. Paste the `setup uri` field, then the
   `setup uri passphrase` field.
4. Let it download. Decline any change to "chunk size" in the config doctor.
5. In General Settings → Extra menus, turn on "Enable advanced features".
   On the 🔌 Customisation sync tab, set a unique device name, turn on
   customisation sync, and apply the items you want from another device.

## Rebuild the Remote

A Rebuild is needed only after a change to encryption settings, or to recover
from corruption. It deletes and recreates the `notes` database, which resets
its access list and puts the Remote in the Remote Lock.

1. On one device, change the LiveSync login to `admin` and the `couchdb admin`
   password. Do not create a Setup URI or a settings QR code while this
   login is set, because both copy the login to the next device.
2. Run the Rebuild from that device and let the upload finish.
3. Restore the access list:
   ```sh
   kubectl -n livesync delete job couchdb-provision
   kustomize build --enable-alpha-plugins --enable-exec livesync | kubectl apply -f -
   ```
4. Change the device login back to `livesync` and the `password` field.
5. Reset each other device from the LiveSync settings ("Reset synchronisation
   on this device").
6. Reset the Vault Mirror (next section).

## Reset the Vault Mirror

Do this after a Rebuild, or when `livesync-cli` logs "remote database is
locked". The steps delete the Vault Mirror's local database and files, but
keep `.git`. Then the Vault Mirror is accepted on the Remote, and it downloads
the Vault again (about 15 minutes for 2,200 files).

```sh
kubectl -n livesync scale deploy/vault-sync --replicas=0
kubectl -n livesync apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: reset-vault-mirror
spec:
  restartPolicy: Never
  containers:
    - name: cli
      image: <the livesync-cli image from vault-sync-deployment.yaml>
      command:
        - sh
        - -c
        - |
          set -e
          rm -rf /data/db/headless-vault-livesync-v2 /data/db/.livesync
          find /data/vault -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
          cli="node /app/dist/index.cjs /data/db --settings /data/db/settings.json"
          id=$($cli remote-ls | awk -F '\t' '$3 == "active" { print $1 }')
          $cli mark-resolved "$id"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: vault-sync-data-lh
EOF
kubectl -n livesync logs -f reset-vault-mirror   # expect "ACCEPTED"
kubectl -n livesync delete pod reset-vault-mirror
kubectl -n livesync scale deploy/vault-sync --replicas=1
```

The volume attaches to one pod at a time, so scale `vault-sync` to 0 before
any one-off pod that mounts it.

## Upgrade

The CLI and the plugin share a sync format. Upgrade the CLI first, then the
plugin on the devices. Never let the plugin get ahead of the CLI.

1. diun reports new `X.Y.Z-cli` tags of `ghcr.io/vrtmrz/livesync-cli`.
2. Change both `livesync-cli` image references in
   `vault-sync-deployment.yaml`, and apply.
3. Check the `livesync-cli` log for "LiveSync active".
4. Update the plugin on each device.

## Restore a note

The Backup holds every committed version. To restore a note, copy it out of
git history (`git show <commit>:<path>`) and paste it into Obsidian on a
device. LiveSync then sends it to every other device.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Device: "Name or password is incorrect" | Wrong field used as the password | Use `password`, not a passphrase |
| Device: "You are not a server admin" | Rebuild with the `livesync` login | Follow "Rebuild the Remote" |
| Device or Vault Mirror: 403 Forbidden | A Rebuild reset the access list | Step 3 of "Rebuild the Remote" |
| Vault Mirror: "remote database is locked" | Remote Lock after a Rebuild | "Reset the Vault Mirror" |
| Vault Mirror: `EMFILE: too many open files, watch` | Node inotify limit | `ansible/k3s-server` sets `fs.inotify.max_user_instances=1024` |
| Vault Mirror: "No sync will occur" | `liveSync` off in the Setup URI | `scripts/configure-cli.sh` forces it on; check the init log |
| No new commits | Push or SSH failure | `kubectl -n livesync logs deploy/vault-sync -c git-backup` |
