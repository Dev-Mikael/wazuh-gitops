# Generated SealedSecrets

This directory is populated by `.github/workflows/generate-wazuh-sealed-secrets.yml`.

The checked-in default has no resources so the repo can render before secrets are
generated. After the workflow runs, it opens a PR that adds:

- `wazuh-api-cred.yaml`
- `wazuh-authd-pass.yaml`
- `wazuh-cluster-key.yaml`
- `dashboard-cred.yaml`
- `indexer-cred.yaml`
- `wazuh-shuffle-webhook.yaml` if `SHUFFLE_WEBHOOK_URL` is supplied
- an updated `kustomization.yaml` listing those files

Only encrypted `SealedSecret` manifests belong here.
