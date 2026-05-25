# Generated Wazuh SealedSecrets

This directory is populated by `.github/workflows/generate-wazuh-sealed-secrets.yml`
or by `scripts/seal-wazuh-secrets.sh` during local testing.

After generation, it contains encrypted manifests such as:

- `wazuh-api-cred.yaml`
- `wazuh-authd-pass.yaml`
- `wazuh-cluster-key.yaml`
- `dashboard-cred.yaml`
- `indexer-cred.yaml`
- `wazuh-otx-api-key.yaml` if `OTX_API_KEY` is supplied
- an updated `kustomization.yaml` listing the generated files

Only encrypted `SealedSecret` manifests belong here. Plaintext `.env` files and raw
Kubernetes `Secret` manifests must not be committed.
