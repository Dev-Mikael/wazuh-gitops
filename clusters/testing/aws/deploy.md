# AWS EKS Wazuh Deployment Runbook

This is the child-level, boss-facing guide for the AWS test deployment.

Important naming note: AWS does not have AKS. AKS is Azure Kubernetes Service. On
AWS, the managed Kubernetes service is EKS. This runbook is for AWS EKS.

## Current Scope

The active deployment now focuses on:

- Wazuh on AWS EKS.
- 8 BIGMODS Windows laptops enrolled into Wazuh.
- Microsoft Defender event collection from those laptops.
- Sysmon telemetry from those laptops.
- AlienVault OTX enrichment through a sealed API key.
- Dashboard access only through private/VPN access.

Shuffle and DFIR-IRIS are pended. Their folders remain in the repo for a later
SOAR/case-management phase, but the active Flux path does not deploy them.

## Simple Mental Model

Think of the setup like a secure office:

- AWS EKS is the building.
- Kubernetes nodes are the rooms where services run.
- Flux is the worker that reads Git and installs what Git says.
- SealedSecrets is the locked safe for passwords and API keys.
- Wazuh manager is the security desk.
- Wazuh indexer is the filing cabinet for security events.
- Wazuh dashboard is the screen the SOC team uses.
- Wazuh agents are reporters installed on the laptops.
- Microsoft Defender is the Windows antivirus/security event source.
- Sysmon is the deep Windows activity recorder.
- AlienVault OTX is the threat-intelligence lookup service.
- VPN is the locked front gate for dashboard access.

The active flow is:

```text
Windows laptops
  -> Wazuh agent
  -> Wazuh manager
  -> Wazuh indexer
  -> Wazuh dashboard

High-severity Wazuh alerts
  -> custom AlienVault OTX integration
  -> OTX API lookup
  -> manager-side enrichment/logging
```

For network IDS:

```text
Laptop traffic
  -> office/VPN/SASE/network inspection path
  -> Suricata or managed NIDS sensor
  -> Wazuh
```

Suricata is not installed on the Windows laptops. It belongs on a network point that
can see the laptop traffic.

## Action Point Status

| Action point | Repo status | Remaining operational work |
|---|---|---|
| Enrol all 8 BIGMODS Windows laptops onto Wazuh | Supported | Install Wazuh agent on each laptop and enroll into `windows-endpoints` |
| Push group settings automatically | Implemented | Verify every agent shows synced group config |
| Wazuh dashboard VPN-only | Implemented at Kubernetes service level with `ClusterIP` | Provide VPN/private ingress/bastion path |
| Microsoft Defender telemetry | Implemented in Windows group config | Confirm Defender events arrive after laptop enrollment |
| AlienVault OTX | Implemented as optional custom integration | Add real `OTX_API_KEY` and regenerate SealedSecrets |
| Network IDS control | Prepared with Suricata sensor group | Deploy a sensor or use managed NIDS where laptop traffic passes |

## Repository Layout

Active AWS test path:

```text
clusters/testing/aws
```

Active production Wazuh path:

```text
clusters/production/wazuh
```

Optional, pended paths:

```text
clusters/testing/aws/shuffle
clusters/testing/aws/dfir-iris
```

## File Walkthrough

### `wazuh-cluster.yaml`

This is the `eksctl` cluster definition for the AWS test cluster.

It creates:

- EKS cluster named `wazuh-soc`.
- Region `us-east-1`.
- Kubernetes version `1.35`.
- OIDC enabled for AWS IAM integration.
- Public and private API endpoint access.
- CloudWatch control-plane logs for API, audit, and authenticator.
- 3 managed worker nodes, scaling up to 5.
- Private worker-node networking.
- Encrypted `gp3` node volumes.
- EKS add-ons including VPC CNI, CoreDNS, kube-proxy, metrics-server, and EBS CSI.

Current node choices:

```text
m6i.xlarge
m6a.xlarge
m7i.xlarge
m7a.xlarge
```

These are enough for Wazuh testing. For a heavier demo or long-running production
pilot, move to `m6i.2xlarge` or similar.

### `clusters/testing/aws/kustomization.yaml`

This is the root Kustomize file used by Flux bootstrap.

It does not deploy Wazuh directly. It applies:

```text
flux-kustomizations.yaml
```

That gives Flux ordered deployment control.

### `clusters/testing/aws/flux-kustomizations.yaml`

This creates two Flux Kustomizations:

- `sealed-secrets`
- `wazuh`

The `wazuh` Kustomization depends on `sealed-secrets`, so Flux installs the secret
controller before applying Wazuh's encrypted secrets.

This is the GitOps-native automation path.

### `clusters/testing/aws/sealed-secrets/`

This installs the Bitnami SealedSecrets controller by Flux HelmRelease.

Files:

- `namespace.yaml` creates the `sealed-secrets` namespace.
- `helm-repository.yaml` tells Flux where the chart is.
- `helm-release.yaml` installs the controller.
- `kustomization.yaml` groups those files.

### `clusters/testing/aws/wazuh/kustomization.yaml`

This points to the real Wazuh deployment:

```text
../../../production/wazuh
```

This keeps one source of truth for Wazuh.

### `clusters/production/wazuh/kustomization.yaml`

This is the main Wazuh build file.

It:

- Loads the official Wazuh Kubernetes base from `upstream/`.
- Loads encrypted secrets from `secrets/sealed/`.
- Creates ConfigMaps for agent groups and custom integrations.
- Applies AWS storage, private service, resource, secret, and bootstrap patches.

### `clusters/production/wazuh/upstream/`

This is a vendored copy of the official Wazuh Kubernetes manifests.

It contains:

- Wazuh namespace.
- Manager master StatefulSet.
- Manager worker StatefulSet.
- Indexer StatefulSet.
- Dashboard Deployment.
- Wazuh services.
- Wazuh default configuration files.
- Certificates generated from the official helper scripts.

Keep direct edits here small. Prefer patches in `patches/`.

### `patches/aws-storage-class.yaml`

This changes Wazuh storage to encrypted AWS EBS `gp3`.

Current Wazuh PVC shape:

```text
3 x indexer PVCs: 50Gi each
1 x manager master PVC: 50Gi
2 x manager worker PVCs: 50Gi each
```

Total declared Wazuh PVC storage:

```text
300Gi
```

### `patches/clusterip-services.yaml`

This is the dashboard privacy control.

It changes Wazuh services to:

```text
ClusterIP
```

That means Kubernetes does not create a public AWS load balancer for the Wazuh
dashboard.

To access the dashboard, use:

- AWS Client VPN plus internal ingress.
- Site-to-site VPN plus internal ingress.
- Bastion host with port-forward for testing.

### `patches/production-resources.yaml`

This sets CPU, memory, and disk sizes for Wazuh.

Current workload shape:

| Component | Replicas | Request per pod | Limit per pod | PVC |
|---|---:|---:|---:|---:|
| Wazuh indexer | 3 | 500m CPU, 1Gi RAM | 1 CPU, 2Gi RAM | 50Gi each |
| Wazuh manager master | 1 | 1 CPU, 1Gi RAM | 2 CPU, 2Gi RAM | 50Gi |
| Wazuh manager worker | 2 | 1 CPU, 1Gi RAM | 2 CPU, 2Gi RAM | 50Gi each |
| Wazuh dashboard | 1 | 500m CPU, 1Gi RAM | 1 CPU, 2Gi RAM | none |

### `patches/delete-default-secrets.yaml`

The official Wazuh manifests include example Kubernetes Secrets.

This patch removes them so public defaults are not deployed. Real values come from
SealedSecrets.

### `secrets/sealed/`

This folder contains encrypted Wazuh SealedSecrets after generation.

Expected files:

```text
wazuh-api-cred.yaml
wazuh-authd-pass.yaml
wazuh-cluster-key.yaml
dashboard-cred.yaml
indexer-cred.yaml
```

Optional:

```text
wazuh-otx-api-key.yaml
```

These encrypted files are safe to commit because only the cluster's SealedSecrets
private key can decrypt them.

### `.github/workflows/generate-wazuh-sealed-secrets.yml`

This workflow automates encrypted secret generation.

It reads plaintext from GitHub Actions secrets, runs `scripts/seal-wazuh-secrets.sh`,
and opens a PR with encrypted manifests.

Plaintext is not committed.

### `scripts/seal-wazuh-secrets.sh`

This is the sealing helper used by CI and local testing.

Required inputs:

```text
KUBESEAL_CERT
WAZUH_API_USERNAME
WAZUH_API_PASSWORD
WAZUH_AUTHD_PASS
WAZUH_CLUSTER_KEY
DASHBOARD_USERNAME
DASHBOARD_PASSWORD
INDEXER_USERNAME
INDEXER_PASSWORD
```

Optional input:

```text
OTX_API_KEY
```

If `OTX_API_KEY` exists, the script creates the encrypted `wazuh-otx-api-key`
SealedSecret. If it does not exist, Wazuh still deploys without OTX lookups.

### `agent-groups/windows-endpoints-agent.conf`

This is the group config for the 8 Windows laptops.

It collects:

```text
Microsoft-Windows-Windows Defender/Operational
Microsoft-Windows-Sysmon/Operational
```

Every Windows laptop should be enrolled into:

```text
windows-endpoints
```

### `agent-groups/suricata-sensors-agent.conf`

This is for future or separate NIDS sensors.

It collects:

```text
/var/log/suricata/eve.json
```

Only use this group for Linux systems or appliances that actually run Suricata.

### `patches/agent-group-bootstrap.yaml`

This patch writes Wazuh group configs into the manager master pod at startup:

```text
/var/ossec/etc/shared/windows-endpoints/agent.conf
/var/ossec/etc/shared/suricata-sensors/agent.conf
```

That is how Wazuh automatically pushes group settings to agents.

It also installs the custom AlienVault OTX integration script into:

```text
/var/ossec/integrations/custom-alienvault-secret
```

### `integrations/custom-alienvault-secret`

This is the custom Wazuh integration script.

It:

- Reads the OTX API key from `/var/ossec/secrets/otx/api_key`.
- Extracts IPs, hashes, URLs, and domains from high-severity Wazuh alerts.
- Queries AlienVault OTX.
- Logs OTX matches from the manager integration path.

### `integrations/manager-integrations.xml`

This documents the active integration block in Wazuh manager config.

The real applied block is in:

```text
upstream/wazuh_managers/wazuh_conf/master.conf
```

## Secrets: How Inputs Work

For production-grade GitOps, use GitHub Actions secrets.

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
```

Optional:

```text
OTX_API_KEY
```

Do not use a committed `.env` file for production. A `.env` file is only a local,
temporary convenience for generating SealedSecrets during testing.

## GitHub Token Rule

Do not paste GitHub tokens into chat, tickets, README files, or commits.

For Flux bootstrap, create a fresh token locally and export it in your terminal only:

```bash
export GITHUB_TOKEN="<new-token-created-locally>"
```

Then run Flux bootstrap from that same terminal. Revoke any token that was pasted
into chat.

## Deployment Flow From Start To Finish

### Phase 1 - Create EKS

Use custom configuration, not quick configuration, because this deployment needs:

- OIDC.
- EBS CSI.
- Private worker nodes.
- Explicit node sizing.
- Control-plane logging.
- Predictable storage.

Create the cluster:

```bash
eksctl create cluster -f wazuh-cluster.yaml --timeout 60m
```

Verify:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Phase 2 - Bootstrap Flux

For full GitOps, use a fresh GitHub token locally, then:

```bash
flux bootstrap github \
  --owner=Dev-Mikael \
  --repository=wazuh-gitops \
  --branch=main \
  --path=clusters/testing/aws \
  --personal
```

This connects the cluster to the Git repo. Flux then reads:

```text
clusters/testing/aws/kustomization.yaml
```

and creates ordered deployment objects from:

```text
clusters/testing/aws/flux-kustomizations.yaml
```

### Phase 3 - Install SealedSecrets

Flux applies:

```text
clusters/testing/aws/sealed-secrets
```

Wait until the controller is ready.

Fetch the public certificate:

```bash
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --fetch-cert \
  > /tmp/sealed-secrets-public-cert.pem
```

Store that public certificate as:

```text
SEALED_SECRETS_PUBLIC_CERT
```

in GitHub Actions secrets.

### Phase 4 - Generate Encrypted Secrets

Add the Wazuh secret inputs in GitHub Actions secrets.

If using AlienVault OTX, also add:

```text
OTX_API_KEY
```

Then run:

```text
Generate Wazuh SealedSecrets
```

Review and merge the PR. The PR should contain encrypted YAML only.

### Phase 5 - Deploy Wazuh

After encrypted secrets are merged, Flux applies:

```text
clusters/testing/aws/wazuh
```

Expected pods:

```text
wazuh-indexer-0
wazuh-indexer-1
wazuh-indexer-2
wazuh-manager-master-0
wazuh-manager-worker-0
wazuh-manager-worker-1
wazuh-dashboard-...
```

Verify:

```bash
kubectl get pods -n wazuh
kubectl get svc -n wazuh
kubectl get pvc -n wazuh
kubectl get secrets -n wazuh
```

All Wazuh services should be `ClusterIP`.

### Phase 6 - Private Dashboard Access

For a quick test:

```bash
kubectl port-forward -n wazuh svc/dashboard 5601:443
```

Open:

```text
https://localhost:5601
```

For real use, put the dashboard behind VPN or internal ingress. Do not expose it with
a public LoadBalancer.

### Phase 7 - Enroll The 8 Windows Laptops

Install the Wazuh agent on each BIGMODS laptop.

Enroll each laptop into:

```text
windows-endpoints
```

The agent enrollment config should include:

```xml
<client>
  <enrollment>
    <groups>windows-endpoints</groups>
  </enrollment>
</client>
```

After enrollment, verify in the Wazuh dashboard:

- All 8 agents appear.
- Each agent is active.
- Each agent belongs to `windows-endpoints`.
- Group config status is synced.
- Defender events appear.
- Sysmon events appear after Sysmon is installed.

## Remote Laptop Reality

The laptops will be assigned to staff and used in the office and at home.

That means there are two traffic cases:

1. Office traffic.
2. Home/remote traffic.

For endpoint monitoring, Wazuh works in both cases as long as the laptop can reach the
Wazuh manager.

For network IDS, a central Suricata sensor only sees traffic that passes through it.
So for home users, choose one:

- Always-on VPN so laptop traffic returns through the office/AWS inspection point.
- SASE/SSE provider with IDS/IPS logging.
- Managed endpoint EDR/NDR product that gives cloud telemetry.

If users work from home with split tunnel and direct internet access, your office
Suricata sensor will not see that home internet traffic.

## Enterprise AV Later

If BIGMODS chooses an enterprise AV or EDR later, Wazuh does not need to be thrown
away.

The pattern becomes:

```text
Enterprise AV/EDR
  -> Windows Event Logs, syslog, API, or SIEM connector
  -> Wazuh
```

Examples:

- Microsoft Defender for Endpoint.
- CrowdStrike.
- SentinelOne.
- Sophos.
- Trend Micro.
- Bitdefender GravityZone.

The exact integration depends on the product. The Wazuh Windows group config can be
extended to collect the vendor event channel if the product writes to Windows Event
Log.

## Sysmon Explanation

Sysmon is a Microsoft Windows monitoring tool.

It records detailed endpoint activity such as:

- Process creation.
- Network connections.
- File creation.
- Driver loads.
- Registry activity.
- PowerShell-related activity when configured.

Defender tells you about malware and protection events. Sysmon tells you what the
machine is doing. Together, they make Wazuh much better for investigation.

## What Is Automated

Automated by GitOps:

- SealedSecrets controller deployment.
- Wazuh deployment.
- Private service configuration.
- Storage class and PVC configuration.
- Agent group config bootstrapping.
- OTX integration script installation.
- Encrypted secret application after SealedSecrets are generated.

Still one-time human/administrator actions:

- Create the AWS cluster or trigger the IaC pipeline that creates it.
- Create GitHub Actions secrets.
- Create and keep the GitHub token locally for Flux bootstrap.
- Get the AlienVault OTX API key from the OTX portal.
- Install Wazuh agents on the laptops through Intune, GPO, RMM, or script.
- Provide VPN/private access to the dashboard.

## Boss-Facing Summary

We are deploying Wazuh as a private Kubernetes-based security monitoring platform on
AWS EKS. The dashboard is not publicly exposed. The 8 Windows laptops will be enrolled
into a central Wazuh group so Microsoft Defender and Sysmon settings are pushed
automatically. Secrets are handled with SealedSecrets, so only encrypted secrets are
stored in Git. AlienVault OTX is integrated through a custom Wazuh integration and
can be enabled as soon as the OTX API key is supplied. Shuffle and DFIR-IRIS are
optional later-phase tools and are not deployed in the current scope.
