# Wazuh Secrets

The official Wazuh Kubernetes manifests include example credentials. This overlay
removes those defaults with `../patches/delete-default-secrets.yaml` so public
example passwords are not deployed by accident.

This repo uses SealedSecrets. The safe production pattern is:

1. Store plaintext values as GitHub Actions secrets.
2. Run the `Generate Wazuh SealedSecrets` workflow.
3. Review and merge the PR containing encrypted `SealedSecret` YAML.
4. Let Flux apply the encrypted manifests to the cluster.

Do not commit `.env` files. A `.env` file is acceptable only as local throwaway input
when testing the sealing script, and it must stay ignored by Git.

## Required Kubernetes Secrets

The Wazuh manifests expect these Secret names and keys in the `wazuh` namespace:

- `wazuh-api-cred`: `username`, `password`
- `wazuh-authd-pass`: `authd.pass`
- `wazuh-cluster-key`: `key`
- `dashboard-cred`: `username`, `password`
- `indexer-cred`: `username`, `password`

Optional AlienVault OTX integration:

- `wazuh-otx-api-key`: `api_key`

## GitHub Actions Secret Inputs

Create these under:

```text
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

Required:

```text
SEALED_SECRETS_PUBLIC_CERT
WAZUH_API_USERNAME
WAZUH_API_PASSWORD
WAZUH_AUTHD_PASS
WAZUH_CLUSTER_KEY
DASHBOARD_USERNAME
DASHBOARD_PASSWORD
INDEXER_USERNAME
INDEXER_PASSWORD
```

Optional:

```text
OTX_API_KEY
```

`OTX_API_KEY` comes from AlienVault OTX. If it is not supplied, Wazuh still deploys;
the custom OTX integration script simply skips lookups until the secret exists.

When changing `indexer-cred.password` or `dashboard-cred.password`, the sealing
workflow also updates the matching bcrypt hashes in:

```text
../upstream/indexer_stack/wazuh-indexer/indexer_conf/internal_users.yml
```

The certificate files under `../upstream/certs/` were generated locally from the
official Wazuh helper scripts. Replace them with environment-specific production
certificates before a real production handoff.
