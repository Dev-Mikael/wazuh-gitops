# Wazuh Production Deployment

This directory deploys Wazuh to Kubernetes with FluxCD and Kustomize. It uses the
official Wazuh Kubernetes manifests, vendored from `wazuh/wazuh-kubernetes` `v4.14.5`,
and layers this repo's production settings on top.

The previous HelmRelease-based install was removed because the production choice is
the official Wazuh Kubernetes manifest set, not a third-party Helm chart.

## What This Installs

- Wazuh manager master and worker nodes.
- Wazuh indexer.
- Wazuh dashboard.
- Internal Kubernetes services for manager API, agent enrollment, agent events, and dashboard.
- AWS-compatible persistent storage through the EBS CSI driver using encrypted `gp3`
  volumes.
- SealedSecrets-ready secret management for the Wazuh API, authd, cluster key,
  dashboard, and indexer credentials.

## File Map

- `kustomization.yaml` - Main Flux/Kustomize entrypoint. It renders the vendored official Wazuh base and applies local production patches.
- `upstream/` - Vendored copy of the official `wazuh/` directory from `wazuh/wazuh-kubernetes` `v4.14.5`. Keep this close to upstream and change it only when a patch cannot be expressed cleanly outside the base.
- `patches/aws-storage-class.yaml` - Replaces the upstream storage class with an AWS EBS CSI `gp3` storage class named `wazuh-storage`.
- `patches/clusterip-services.yaml` - Keeps Wazuh manager and dashboard services private by changing them from `LoadBalancer` to `ClusterIP`.
- `patches/production-resources.yaml` - Sets production-oriented CPU, memory, and PVC sizes for indexer, manager, worker, and dashboard.
- `patches/delete-default-secrets.yaml` - Removes the upstream example Kubernetes Secrets so generated SealedSecrets can own the real secret names.
- `secrets/sealed/` - Destination for generated encrypted Wazuh SealedSecrets. Empty until the generation workflow runs.
- `agent-groups/windows-endpoints-agent.conf` - Centralized Wazuh agent group config for Windows laptops. It collects Microsoft Defender and Sysmon event channels.
- `agent-groups/suricata-sensors-agent.conf` - Centralized Wazuh agent group config for dedicated Suricata network IDS sensors. It collects `/var/log/suricata/eve.json`.
- `patches/agent-group-bootstrap.yaml` - Adds an init container to the Wazuh manager master that writes the Windows and Suricata group `agent.conf` files into `/var/ossec/etc/shared`.
- `integrations/manager-integrations.xml` - Documents the Wazuh manager integration block for Shuffle. Use Shuffle to fan out to DFIR-IRIS and AlienVault OTX enrichment.
- `integrations/custom-shuffle-secret` - Custom Wazuh integration script that forwards alerts to Shuffle while reading the real webhook URL from a mounted Kubernetes Secret.
- `secrets/README.md` - Lists the required production secrets and the expected Kubernetes secret names/keys.

AWS testing files live outside this production directory:

- `clusters/testing/aws/sealed-secrets/` - Installs the SealedSecrets controller with Flux Helm.
- `clusters/production/wazuh/` - Wazuh deployment path for the AWS test cluster.
- `.github/workflows/generate-wazuh-sealed-secrets.yml` - Generates encrypted SealedSecrets from GitHub Actions secrets and opens a PR.
- `scripts/seal-wazuh-secrets.sh` - Local/CI helper used by the workflow. It does not commit plaintext secrets.

## Prerequisites

- EKS or another AWS Kubernetes cluster with FluxCD installed.
- AWS EBS CSI driver installed.
- `kubectl` access to the cluster.
- A private DNS or internal ingress path for Wazuh dashboard access.
- Real production secrets for Wazuh API, authd enrollment, cluster key, dashboard, and indexer.
- Windows endpoints ready for Wazuh agent deployment through Intune, GPO, RMM, or PowerShell.

## Deployment Steps

1. Install the SealedSecrets controller.

   Apply the Flux path `clusters/testing/aws/sealed-secrets` before applying Wazuh.
   This installs the Bitnami SealedSecrets controller.

2. Generate encrypted SOC platform SealedSecrets.

   Use the GitHub Actions workflow named `Generate SOC Platform SealedSecrets`. It
   reads GitHub Actions secrets, generates encrypted `SealedSecret` manifests for
   Wazuh, Shuffle, and DFIR-IRIS, updates the Wazuh indexer bcrypt hashes, and opens
   a PR.

   Required secret names and keys:

   ```text
   wazuh-api-cred: username, password
   wazuh-authd-pass: authd.pass
   wazuh-cluster-key: key
   dashboard-cred: username, password
   indexer-cred: username, password
   wazuh-shuffle-webhook: hook_url (optional, after Shuffle workflow exists)
   ```

   Add these in GitHub under:

   ```text
   Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
   ```

   Required GitHub Actions secret inputs:

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

   For local testing only, copy `.env.example` to `.env`, fill the values, then run:

   ```bash
   set -a
   . ./.env
   set +a
   bash scripts/seal-wazuh-secrets.sh
   ```

   Do not commit `.env`.

3. Replace generated certificates for production.

   The files under `upstream/certs/` were generated from the official Wazuh helper
   scripts so Kustomize can render and Flux can deploy. For production, regenerate
   certificates for your environment or replace them with your certificate-management
   process before first deployment.

4. Confirm storage settings.

   The included storage class uses AWS EBS CSI:

   ```yaml
   provisioner: ebs.csi.aws.com
   parameters:
     type: gp3
     encrypted: "true"
   ```

   Change `patches/aws-storage-class.yaml` if your test cluster uses a different
   AWS storage policy.

5. Confirm private access.

   `patches/clusterip-services.yaml` keeps the dashboard and manager service private.
   Expose dashboard access with an internal ingress, VPN, bastion, or port-forward.

6. Commit and push.

   Flux should be pointed at this path:

   ```bash
   clusters/production/wazuh
   ```

   Flux will build `kustomization.yaml` from the vendored official Wazuh base and
   apply the local patches.

7. Check Flux and Wazuh status.

   ```bash
   flux get kustomizations
   kubectl get pods -n wazuh
   kubectl get svc -n wazuh
   kubectl get pvc -n wazuh
   ```

8. Access the dashboard privately.

   For a quick check:

   ```bash
   kubectl port-forward -n wazuh svc/dashboard 5601:443
   ```

   Then open `https://localhost:5601`.

## Integrations

### Shuffle

Wazuh officially supports forwarding alerts to Shuffle with the Wazuh Integrator
module. The native integration requires the Shuffle hook URL directly inside
`ossec.conf`, which would leak a secret if committed to Git.

This repo uses a safer production pattern:

- `master.conf` enables a custom integration named `custom-shuffle-secret`.
- `integrations/custom-shuffle-secret` forwards qualifying Wazuh alerts to Shuffle.
- The real Shuffle webhook URL is read from the optional Kubernetes Secret named
  `wazuh-shuffle-webhook`.
- The sealing script creates that Secret only when `SHUFFLE_WEBHOOK_URL` is present
  in GitHub Actions secrets.

This keeps the deployment automated without committing the plaintext webhook URL.
For the AWS test path, Shuffle images are currently referenced with `latest`; pin
tested tags before a final production handoff.

Recommended flow:

```text
Wazuh alert -> Shuffle webhook -> enrichment/automation -> DFIR-IRIS case
```

### DFIR-IRIS

Use Shuffle as the integration point for DFIR-IRIS. DFIR-IRIS replaces TheHive in
this design because the current requirement is an open-source case management path
without a commercial-trial dependency. In Shuffle, create a workflow triggered by the
Wazuh webhook and add DFIR-IRIS actions or HTTP API calls for alert triage and case
creation.

Store these values in the Shuffle secret store or GitHub Actions secrets for workflow
generation, not in Wazuh ConfigMaps:

```text
DFIR_IRIS_URL
DFIR_IRIS_API_KEY
```

### AlienVault OTX

Use AlienVault OTX inside the Shuffle workflow for enrichment. This is cleaner than
placing an OTX API key directly into Wazuh manager config. If you later want native
Wazuh-side OTX enrichment, implement it as a `custom-*` Wazuh integration script and
mount that script into the manager.

Store this value in the Shuffle secret store or GitHub Actions secrets:

```text
OTX_API_KEY
```

### Microsoft Defender

Microsoft Defender Antivirus logs belong in the Windows endpoint agent group, not in
the Wazuh manager Helm/Kustomize config.

Use `agent-groups/windows-endpoints-agent.conf` for the `windows-endpoints` group.
Wazuh already includes Windows Defender decoders and rules.

This repo now bootstraps that group configuration automatically through
`patches/agent-group-bootstrap.yaml`.

### Suricata

Suricata is the network IDS control path. It is not installed on the 8 Windows
laptops in this design. Instead, deploy Suricata on a dedicated network sensor or
managed network inspection point that can see the laptops' traffic, then install the
Wazuh agent on that sensor.

Use `agent-groups/suricata-sensors-agent.conf` for Suricata sensors. Wazuh parses
`/var/log/suricata/eve.json` JSON events and surfaces Suricata alerts in the
dashboard.

This repo now bootstraps that group configuration automatically through
`patches/agent-group-bootstrap.yaml`.

For a Windows-only endpoint rollout, the Suricata sensor is a separate control
component, not a ninth monitored endpoint. Put it where Windows laptop traffic passes,
such as the office firewall, VPN egress, SPAN/TAP port, or an AWS inspection path.
Until that sensor exists and has traffic visibility, the Suricata group is only
prepared configuration and does not produce network IDS alerts.

### ClamAV

ClamAV is intentionally not configured here because the current focus is Windows
laptops. Add a separate Linux endpoint group later if ClamAV becomes part of scope.

## Agent Groups And Enrollment

Create these Wazuh groups:

```text
windows-endpoints
suricata-sensors
```

You can create and manage groups from the Wazuh dashboard under agent management, or
through the Wazuh API.

For Windows laptop enrollment, enroll agents directly into the Windows group. The
agent-side enrollment config should include:

```xml
<client>
  <enrollment>
    <groups>windows-endpoints</groups>
  </enrollment>
</client>
```

The group must exist before enrollment, otherwise enrollment into that group can fail.

## Validation Commands

Render the manifests locally:

```bash
kubectl kustomize clusters/production/wazuh
```

Apply manually if Flux is not being used:

```bash
kubectl apply -k clusters/production/wazuh
```

Force Flux reconciliation:

```bash
flux reconcile kustomization wazuh
```

## AWS Test Flow

Use this path for a temporary AWS Kubernetes test cluster:

```text
clusters/testing/aws/sealed-secrets
clusters/testing/aws/wazuh
clusters/testing/aws/shuffle
clusters/testing/aws/dfir-iris
```

The intended order is:

1. Flux applies `clusters/testing/aws/sealed-secrets` first.
2. The SealedSecrets controller creates or uses its sealing key.
3. Store the controller public certificate in the GitHub Actions secret named `SEALED_SECRETS_PUBLIC_CERT`.
4. Store the Wazuh, Shuffle, and DFIR-IRIS secret values as GitHub Actions secrets.
5. Run the `Generate SOC Platform SealedSecrets` workflow.
6. Review and merge the generated PR containing only encrypted `SealedSecret` manifests.
7. Flux applies `clusters/testing/aws/wazuh`, then `clusters/testing/aws/shuffle`,
   then `clusters/testing/aws/dfir-iris`.

This keeps the deployment automated after merge. The only sensitive values live in
GitHub Actions secrets and inside the cluster; plaintext is not committed.

Do not use a committed `.env` for production or boss-facing handoff. A `.env` file is
acceptable only as a local throwaway input while generating SealedSecrets, and it must
stay in `.gitignore`. For production-grade GitOps, prefer SealedSecrets, SOPS with
age/KMS, External Secrets Operator with AWS Secrets Manager, or another managed secret
store. Since your stated choice is SealedSecrets, keep the real values in GitHub
Actions secrets and commit only encrypted `SealedSecret` YAML.

## References

- Official Wazuh Kubernetes manifests: `https://github.com/wazuh/wazuh-kubernetes`
- Wazuh external integrations: `https://documentation.wazuh.com/current/user-manual/manager/integration-with-external-apis.html`
- Wazuh Windows Defender collection: `https://documentation.wazuh.com/current/user-manual/capabilities/malware-detection/win-defender-logs-collection.html`
- Wazuh Suricata integration: `https://documentation.wazuh.com/current/proof-of-concept-guide/integrate-network-ids-suricata.html`
- Shuffle self-hosted install guide: `https://github.com/Shuffle/Shuffle/blob/main/.github/install-guide.md`
- DFIR-IRIS documentation: `https://docs.dfir-iris.org/`
