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

Secrets are mananaged using [Sops]. Files containing secret values must be
edited with `sops edit <file>`.

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

## Ansible

I don't want to be forced to use kubernetes for everything, so I still maintain
parts of the infrastructure outside of k8s. For those services I'm trying to
write ansible playbooks so I can store that infrastructure as code. These live
in the `ansible/` directory.
