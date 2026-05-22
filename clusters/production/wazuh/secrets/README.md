# SOC Platform Secrets

The official Wazuh Kubernetes manifests include example credentials. This overlay
removes those example Secrets so public defaults are not deployed by accident.

This repository is configured for SealedSecrets. The upstream Wazuh example Secrets
are removed by `../patches/delete-default-secrets.yaml`, and generated SealedSecrets
must provide the same secret names and keys.

For your AWS test flow:

- Install the controller from `clusters/testing/aws/sealed-secrets`.
- Generate encrypted secret manifests with `.github/workflows/generate-wazuh-sealed-secrets.yml`.
- Deploy Wazuh from `clusters/testing/aws/wazuh`.
- Deploy Shuffle from `clusters/testing/aws/shuffle`.
- Deploy DFIR-IRIS from `clusters/testing/aws/dfir-iris`.

The generated encrypted manifests land in:

```text
clusters/production/wazuh/secrets/sealed/
clusters/testing/aws/shuffle/secrets/sealed/
clusters/testing/aws/dfir-iris/secrets/sealed/
```

Do not commit `.env` files. They are not production-grade secret storage. They are
useful only as local temporary input, and even then they must stay outside Git.

Required secret names and keys:

- `wazuh-api-cred`: `username`, `password`
- `wazuh-authd-pass`: `authd.pass`
- `wazuh-cluster-key`: `key`
- `dashboard-cred`: `username`, `password`
- `indexer-cred`: `username`, `password`
- `wazuh-shuffle-webhook`: `hook_url` (optional, generated after the Shuffle workflow exists)
- `shuffle-secrets`: `OPENSEARCH_INITIAL_ADMIN_PASSWORD`, `SHUFFLE_OPENSEARCH_PASSWORD`, `SHUFFLE_ENCRYPTION_MODIFIER`, `SHUFFLE_DEFAULT_USERNAME`, `SHUFFLE_DEFAULT_PASSWORD`, `SHUFFLE_DEFAULT_APIKEY`
- `dfir-iris-secrets`: `POSTGRES_PASSWORD`, `POSTGRES_ADMIN_USER`, `POSTGRES_ADMIN_PASSWORD`, `IRIS_SECRET_KEY`, `IRIS_SECURITY_PASSWORD_SALT`, `IRIS_ADM_PASSWORD`, `IRIS_ADM_API_KEY`

You input the plaintext values as GitHub Actions secrets, not as files in this repo.

Go to:

```text
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

Create:

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
SHUFFLE_OPENSEARCH_PASSWORD
SHUFFLE_ENCRYPTION_MODIFIER
SHUFFLE_DEFAULT_USERNAME
SHUFFLE_DEFAULT_PASSWORD
SHUFFLE_DEFAULT_APIKEY
DFIR_IRIS_POSTGRES_PASSWORD
DFIR_IRIS_POSTGRES_ADMIN_USER
DFIR_IRIS_POSTGRES_ADMIN_PASSWORD
DFIR_IRIS_SECRET_KEY
DFIR_IRIS_SECURITY_PASSWORD_SALT
DFIR_IRIS_ADMIN_PASSWORD
DFIR_IRIS_ADMIN_API_KEY
```

Optional after the Shuffle workflow exists:

```text
SHUFFLE_WEBHOOK_URL
```

Then run the `Generate SOC Platform SealedSecrets` workflow.

When changing `indexer-cred.password` or `dashboard-cred.password`, update the
matching bcrypt hashes for `admin` and `kibanaserver` in
`../upstream/indexer_stack/wazuh-indexer/indexer_conf/internal_users.yml`.

The certificate files under `../upstream/certs/` were generated locally from the
official Wazuh helper scripts. Replace them with environment-specific production
certificates before deploying to a real cluster.
