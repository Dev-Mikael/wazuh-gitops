# AWS Wazuh Test Deployment

This directory is the AWS EKS test path for the current active scope:

- Wazuh manager, indexer, and dashboard.
- Microsoft Defender and Sysmon telemetry from Windows laptops.
- Optional AlienVault OTX enrichment through a sealed API key.

Shuffle and DFIR-IRIS manifests remain in this repo for a later SOAR/case-management
phase, but they are intentionally not part of the active Flux path right now.

## Flow

1. Bootstrap Flux to this directory.
2. Flux applies `flux-kustomizations.yaml`.
3. Flux installs SealedSecrets from `sealed-secrets/`.
4. After SealedSecrets is ready, Flux deploys Wazuh from `wazuh/`.
5. The Wazuh manager pushes the `windows-endpoints` group config to enrolled laptops.

## Active Directories

- `kustomization.yaml` - Root Kustomize entrypoint used by Flux bootstrap.
- `flux-kustomizations.yaml` - Creates ordered Flux Kustomizations for SealedSecrets and Wazuh.
- `sealed-secrets/` - Flux HelmRepository and HelmRelease for Bitnami SealedSecrets.
- `wazuh/` - Pointer to `../../production/wazuh`, the main Wazuh deployment.
- `../../production/wazuh/` - Official Wazuh Kubernetes base plus AWS, secrets, endpoint group, and OTX patches.

## Optional Directories

- `shuffle/` - Self-hosted Shuffle SOAR, pended for a later phase.
- `dfir-iris/` - DFIR-IRIS case management, pended for a later phase.

## Secrets

Use GitHub Actions secrets and SealedSecrets for production-grade GitOps. Do not
commit `.env` files.

Required GitHub Actions secrets:

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

Run the `Generate Wazuh SealedSecrets` workflow after those values exist. It opens a
pull request containing encrypted `SealedSecret` YAML only.

Read `deploy.md` for the child-level walkthrough and boss-facing explanation.
