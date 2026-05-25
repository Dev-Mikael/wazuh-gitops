# Wazuh Production Deployment

This directory deploys Wazuh to Kubernetes with FluxCD and Kustomize. It uses the
official Wazuh Kubernetes manifests, vendored from `wazuh/wazuh-kubernetes` `v4.14.5`,
with local AWS, secret-management, Windows endpoint, and AlienVault OTX patches.

The previous HelmRelease-based Wazuh install was removed because the production fit
is the official Wazuh Kubernetes manifest set, not a third-party Helm chart.

## What This Installs

- Wazuh manager master and worker nodes.
- Wazuh indexer.
- Wazuh dashboard.
- Internal Kubernetes services for manager API, agent enrollment, agent events, and dashboard.
- AWS EBS CSI `gp3` encrypted persistent storage.
- SealedSecrets-ready credentials for Wazuh API, authd enrollment, cluster key,
  dashboard, and indexer.
- Windows endpoint group configuration for Microsoft Defender and Sysmon telemetry.
- Optional AlienVault OTX enrichment using a sealed `wazuh-otx-api-key` Secret.

Shuffle and DFIR-IRIS are intentionally pended. Their manifests can stay in the repo
for a later phase, but they are not part of the active Wazuh deployment path.

## File Map

- `kustomization.yaml` - Main Kustomize entrypoint. It renders the official Wazuh base, generated SealedSecrets, ConfigMaps, and patches.
- `upstream/` - Vendored official Wazuh Kubernetes manifests. Keep this close to upstream.
- `patches/aws-storage-class.yaml` - Replaces upstream storage with encrypted AWS EBS CSI `gp3`.
- `patches/clusterip-services.yaml` - Keeps dashboard, manager, workers, and indexer private with `ClusterIP` services.
- `patches/production-resources.yaml` - Sets CPU, memory, and PVC sizing.
- `patches/delete-default-secrets.yaml` - Removes upstream example Secrets.
- `patches/agent-group-bootstrap.yaml` - Copies group configs and the OTX integration script into the Wazuh manager master pod.
- `agent-groups/windows-endpoints-agent.conf` - Group config for BIGMODS Windows laptops. Collects Microsoft Defender and Sysmon logs.
- `agent-groups/suricata-sensors-agent.conf` - Prepared group config for dedicated Suricata NIDS sensors.
- `integrations/custom-alienvault-secret` - Custom Wazuh integration script that reads the OTX API key from a mounted Secret.
- `integrations/manager-integrations.xml` - Documents the active OTX integration block in `master.conf`.
- `secrets/sealed/` - Generated encrypted SealedSecrets.
- `secrets/README.md` - Secret names, keys, and input process.

AWS testing files live in:

```text
clusters/testing/aws
```

## Secret Handling

Use SealedSecrets for GitOps. Do not use a committed `.env` file for production.

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

Run the GitHub Actions workflow named `Generate Wazuh SealedSecrets`. It creates a PR
with encrypted SealedSecrets and updates the indexer bcrypt hashes for the supplied
dashboard and indexer passwords.

For local testing only:

```bash
set -a
. ./.env
set +a
bash scripts/seal-wazuh-secrets.sh clusters/production/wazuh/secrets/sealed
```

Keep `.env` ignored and delete local plaintext copies when testing is complete.

## Deployment Order

For GitOps on AWS EKS:

1. Create the EKS cluster.
2. Install or bootstrap Flux.
3. Install SealedSecrets.
4. Generate and merge encrypted Wazuh SealedSecrets.
5. Deploy Wazuh from `clusters/testing/aws/wazuh` or `clusters/production/wazuh`.
6. Enroll Windows laptops into the `windows-endpoints` group.
7. Verify dashboard access is private only.

For the current AWS test path, Flux should point to:

```text
clusters/testing/aws
```

That path creates ordered Flux Kustomizations for SealedSecrets first, then Wazuh.
Shuffle and DFIR-IRIS are not included in that active Flux path.

## Integrations

### Microsoft Defender

Microsoft Defender Antivirus logs are collected from each Windows laptop by the Wazuh
agent. They belong in the Windows agent group config, not in Kubernetes manager
configuration.

Active file:

```text
agent-groups/windows-endpoints-agent.conf
```

That file collects:

```text
Microsoft-Windows-Windows Defender/Operational
Microsoft-Windows-Sysmon/Operational
```

### Sysmon

Sysmon is not antivirus. It is deep Windows endpoint telemetry. It records activity
such as process creation, network connections, driver loads, registry changes, and
file creation events. Wazuh uses those events for detection and investigation.

Install Sysmon on the laptops with an approved configuration, then enroll the Wazuh
agent into the `windows-endpoints` group.

### AlienVault OTX

AlienVault OTX is integrated with a custom Wazuh integration named:

```text
custom-alienvault-secret
```

The manager config enables this for level 7+ alerts. The script reads the API key
from:

```text
/var/ossec/secrets/otx/api_key
```

That file is mounted from the optional Kubernetes Secret:

```text
wazuh-otx-api-key
```

If `OTX_API_KEY` is not provided, Wazuh still deploys and the script skips lookups.

### Suricata / NIDS

Suricata is the network IDS control path. It is not installed on the 8 Windows
laptops in this design. Put Suricata on a network point that can see laptop traffic:

- Office firewall or gateway.
- VPN egress.
- SPAN/TAP-connected sensor.
- AWS inspection VPC path.
- SASE/SSE provider that exports IDS/IPS logs.

Use:

```text
agent-groups/suricata-sensors-agent.conf
```

for dedicated Linux Suricata sensors that run the Wazuh agent and collect:

```text
/var/log/suricata/eve.json
```

For staff who work at home, central NIDS only works if traffic passes through your
VPN, SASE, or another managed inspection path. If laptops use split tunneling and go
directly to the internet, Wazuh still gives endpoint telemetry, but the central NIDS
sensor will not see that home traffic.

### Enterprise AV Later

If BIGMODS later buys an enterprise AV or EDR product, keep this Wazuh design. Replace
or extend the Windows group collection with the vendor's supported telemetry path:

- Windows Event Channel collection if the product writes event logs.
- Syslog/API ingestion if the product exports alerts centrally.
- Vendor integration through a future SOAR phase.

Microsoft Defender can remain as a telemetry source if it is still enabled by policy.

## Agent Groups And Enrollment

Create these Wazuh groups:

```text
windows-endpoints
suricata-sensors
```

For the current endpoint scope, enroll the 8 Windows laptops into:

```text
windows-endpoints
```

The agent-side enrollment config should include:

```xml
<client>
  <enrollment>
    <groups>windows-endpoints</groups>
  </enrollment>
</client>
```

The group must exist before enrollment, otherwise enrollment into that group can
fail. You can create and manage groups from the Wazuh dashboard or Wazuh API.

## Private Access

`patches/clusterip-services.yaml` keeps the dashboard private. It must be accessed
through a private path such as:

- AWS Client VPN plus internal ingress.
- Site-to-site VPN plus internal ingress.
- Bastion host and `kubectl port-forward` for testing.

Quick local check:

```bash
kubectl port-forward -n wazuh svc/dashboard 5601:443
```

Then open:

```text
https://localhost:5601
```

## Validation Commands

Render locally:

```bash
kubectl kustomize clusters/production/wazuh
```

Apply manually only for testing outside Flux:

```bash
kubectl apply -k clusters/production/wazuh
```

Check status:

```bash
kubectl get pods -n wazuh
kubectl get svc -n wazuh
kubectl get pvc -n wazuh
kubectl get secrets -n wazuh
```

## References

- Official Wazuh Kubernetes manifests: `https://github.com/wazuh/wazuh-kubernetes`
- Wazuh external integrations: `https://documentation.wazuh.com/current/user-manual/manager/integration-with-external-apis.html`
- Wazuh Windows Defender collection: `https://documentation.wazuh.com/current/user-manual/capabilities/malware-detection/win-defender-logs-collection.html`
- Wazuh Suricata integration: `https://documentation.wazuh.com/current/proof-of-concept-guide/integrate-network-ids-suricata.html`
