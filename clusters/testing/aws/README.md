# AWS SOC Test Deployment

This directory is the AWS test path for Wazuh, Shuffle, and DFIR-IRIS before handing
the production approach to leadership.

## Flow

1. Flux installs the SealedSecrets controller from `sealed-secrets/`.
2. CI generates encrypted `SealedSecret` manifests from GitHub Actions secrets.
3. Flux deploys Wazuh from `clusters/production/wazuh`.
4. Flux deploys self-hosted Shuffle from `shuffle/`.
5. Flux deploys DFIR-IRIS from `dfir-iris/`.

## Directories

- `sealed-secrets/` - Flux HelmRepository and HelmRelease for Bitnami SealedSecrets.
- `wazuh/` - Small Kustomize pointer to `../../production/wazuh`.
- `shuffle/` - Self-hosted Shuffle SOAR deployment.
- `dfir-iris/` - Self-hosted DFIR-IRIS case-management deployment.
- `../../production/wazuh/` - The actual Wazuh AWS test deployment using the official Wazuh Kubernetes base, AWS EBS CSI storage, and generated SealedSecrets.

Read `deploy.md` for the full step-by-step walkthrough.

## AWS Requirements

- EKS or another AWS Kubernetes cluster.
- AWS EBS CSI driver installed.
- Nodes allowed to provision encrypted EBS `gp3` volumes.
- FluxCD installed and watching this repository.
- The SealedSecrets controller applied before Wazuh, Shuffle, and DFIR-IRIS.

## Secret Source

Use GitHub Actions secrets, not a committed `.env` file.

Required GitHub Actions secrets:

- `SEALED_SECRETS_PUBLIC_CERT`
- `WAZUH_API_USERNAME`
- `WAZUH_API_PASSWORD`
- `WAZUH_AUTHD_PASS`
- `WAZUH_CLUSTER_KEY`
- `DASHBOARD_USERNAME`
- `DASHBOARD_PASSWORD`
- `INDEXER_USERNAME`
- `INDEXER_PASSWORD`
- `SHUFFLE_OPENSEARCH_PASSWORD`
- `SHUFFLE_ENCRYPTION_MODIFIER`
- `SHUFFLE_DEFAULT_USERNAME`
- `SHUFFLE_DEFAULT_PASSWORD`
- `SHUFFLE_DEFAULT_APIKEY`
- `DFIR_IRIS_POSTGRES_PASSWORD`
- `DFIR_IRIS_POSTGRES_ADMIN_USER`
- `DFIR_IRIS_POSTGRES_ADMIN_PASSWORD`
- `DFIR_IRIS_SECRET_KEY`
- `DFIR_IRIS_SECURITY_PASSWORD_SALT`
- `DFIR_IRIS_ADMIN_PASSWORD`
- `DFIR_IRIS_ADMIN_API_KEY`

Optional after the Shuffle workflow exists:

- `SHUFFLE_WEBHOOK_URL`

After those exist, run the `Generate SOC Platform SealedSecrets` workflow. It opens
a PR with encrypted SealedSecret YAML only.

## DevSecOps Notes

- Keep Wazuh, Shuffle, and DFIR-IRIS services private by default.
- Use internal ingress, VPN, or SSO-aware access in front of the Wazuh dashboard,
  Shuffle UI, and DFIR-IRIS UI.
- Treat Wazuh, Shuffle, DFIR-IRIS, OTX, and integration credentials as
  high-sensitivity secrets.
- Rotate test credentials before using the same pattern for production.
- Replace generated test certificates before production handoff.
