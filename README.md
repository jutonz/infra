# Infra

This repo contains kubernetes (k8s) config files and ansible playbooks for
services I run locally.

## Kubernetes

Previously I ran many services as `docker-compose.yaml` files, but I decided to
convert them to k8s for ease of management in the long term.

I'm trying out [kustomize] for config management. Most services can be deployed
with `kubectl apply -k <dir>`. These directories provide a `kustomization.yaml`
file which says which resources to apply.

[kustomize]: https://kustomize.io/

### Setup

1. Install and setup [direnv](https://github.com/direnv/direnv)
2. `brew install sops`
3. Install [ksops](https://github.com/viaduct-ai/kustomize-sops?tab=readme-ov-file#installation)


### Secrets

Secrets are managed using [Sops]. Files containing secret values must be
edited with `sops edit <file>`. __Do not edit sops-encrypted files any other way.__

These files also require special handling when passing to `kubectl` since the
secret values must first be decrypted. This can be done manully via:

```bash
sops decrypt <file> | kubectl apply -f -
```

To automate this I've utilized a kustomize plugin, [ksops]. This works by
adding a generator that will decrypt Sops-encrypted files prior to passing them
to kubectl.

You can use the `bin/update` script when applying resources, which will go
through all serivces and apply defintions for all resources.

[Sops]: https://github.com/getsops/sops
[ksops]: https://github.com/viaduct-ai/kustomize-sops

__Creating new secrets__

Create the file as you normally would, then run this to encrypt it:

```bash
sops encrypt --encrypted-regex '^(data|stringData)$' --in-place path/to/file.yaml
```

The `--encrypted-regex` flag tells sops to only encrypt the `data` and
`stringData` values, leaving the rest in plaintext. This makes these files
easier to read in their encrypted state.


## Ansible

I don't want to be forced to use kubernetes for everything, so I still maintain
parts of the infrastructure outside of k8s. For those services I'm trying to
write ansible playbooks so I can store that infrastructure as code. These live
in the `ansible/` directory.
