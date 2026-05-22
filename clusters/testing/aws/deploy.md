# AWS Wazuh Deployment Runbook

This guide explains the whole setup in simple language, then gives the technical
details you need to explain it to your boss.

Important naming note: AWS does not have AKS. AKS is Azure Kubernetes Service. On
AWS, the managed Kubernetes service is EKS. This runbook is for AWS EKS.

## What We Are Building

We are building a private Wazuh security monitoring platform on AWS Kubernetes.

Wazuh will receive logs and security events from TUROG endpoints. The first endpoint
scope is:

```text
8 TUROG Windows laptops
```

The target outcome is:

```text
Windows laptops
  -> Wazuh agent
  -> Wazuh manager
  -> Wazuh indexer
  -> Wazuh dashboard
  -> Shuffle
  -> AlienVault OTX enrichment
  -> DFIR-IRIS alert/case
```

## Child-Level Mental Model

Think of this like a secured office.

- AWS EKS is the building.
- FluxCD is the worker that reads our Git repository and installs what the repo says.
- SealedSecrets is the locked safe. It lets us keep encrypted secrets in Git.
- Wazuh is the security desk.
- Wazuh agents are the security reporters installed on laptops.
- Shuffle is the automation assistant.
- AlienVault OTX is the threat intelligence lookup book.
- DFIR-IRIS is the incident case notebook.
- VPN is the front gate. Nobody should reach the dashboard from the public internet.

The safe order is:

```text
Build AWS EKS
  -> Install Flux
  -> Install SealedSecrets
  -> Generate encrypted SOC platform secrets
  -> Deploy Wazuh
  -> Deploy self-hosted Shuffle
  -> Deploy self-hosted DFIR-IRIS
  -> Enroll the 8 Windows laptops
  -> Send Wazuh alerts to Shuffle
  -> Shuffle enriches with OTX
  -> Shuffle creates alerts or cases in DFIR-IRIS
```

## Current Action Point Status

| Action point | Status in this repo | Remaining work |
|---|---|---|
| Enroll all 8 TUROG Windows laptops onto Wazuh | Supported by the Wazuh deployment and `windows-endpoints` group config | Install Wazuh agent on each laptop and enroll each one into `windows-endpoints` |
| Set up group configuration so settings push automatically | Implemented by `patches/agent-group-bootstrap.yaml` and `agent-groups/windows-endpoints-agent.conf` | Verify each agent shows `group_config_status: synced` |
| Ensure Wazuh dashboard is VPN-only, not public | Kubernetes services are patched to `ClusterIP`, so no public LoadBalancer is created | Provide VPN/private network path, such as AWS Client VPN plus internal ingress or bastion |

## Repository Layout

AWS testing has four entrypoints:

```text
clusters/testing/aws/sealed-secrets
clusters/testing/aws/wazuh
clusters/testing/aws/shuffle
clusters/testing/aws/dfir-iris
```

The actual Wazuh files live here:

```text
clusters/production/wazuh
```

That may look odd at first, but it keeps one source of truth for Wazuh. The AWS test
folder points to that Wazuh deployment instead of copying it.

## File-By-File Walkthrough

### `clusters/testing/aws/sealed-secrets/`

This installs the SealedSecrets controller.

- `namespace.yaml` creates the `sealed-secrets` namespace.
- `helm-repository.yaml` tells Flux where the SealedSecrets Helm chart is.
- `helm-release.yaml` tells Flux to install the SealedSecrets controller.
- `kustomization.yaml` groups those files together.

SealedSecrets must be installed before Wazuh because Wazuh needs secrets such as API
passwords, enrollment password, dashboard password, and indexer password.

### `clusters/testing/aws/wazuh/kustomization.yaml`

This is a small pointer file.

It tells Kustomize:

```text
Use ../../../production/wazuh
```

That means the AWS test path deploys the main Wazuh deployment without copying it.

### `clusters/production/wazuh/kustomization.yaml`

This is the main Wazuh build file.

It does five important things:

1. Loads the official Wazuh Kubernetes manifests from `upstream/`.
2. Loads encrypted SealedSecrets from `secrets/sealed/`.
3. Creates a ConfigMap containing endpoint group configs.
4. Applies AWS storage and service patches.
5. Applies the bootstrap patch that writes group configs into Wazuh.

### `clusters/production/wazuh/upstream/`

This is a vendored copy of the official Wazuh Kubernetes manifests.

It contains the base Wazuh objects:

- Namespace.
- Wazuh manager master.
- Wazuh manager workers.
- Wazuh indexer.
- Wazuh dashboard.
- Default services.
- Default config.
- Generated local certificates.

We keep this close to the official upstream layout. Local changes are mostly done in
`patches/`.

### `patches/aws-storage-class.yaml`

This changes Wazuh storage to AWS EBS CSI:

```yaml
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
```

Wazuh uses persistent disks for the indexer and manager data. In the current patch,
the rendered storage is:

```text
3 x Wazuh indexer PVCs: 50Gi each
1 x Wazuh manager master PVC: 50Gi
2 x Wazuh manager worker PVCs: 50Gi each
```

Expected Wazuh PVC total:

```text
300Gi
```

The full SOC test stack adds more storage:

```text
Shuffle OpenSearch PVC: 50Gi
Shuffle files PVC: 20Gi
DFIR-IRIS PostgreSQL PVC: 20Gi
DFIR-IRIS downloads PVC: 20Gi
DFIR-IRIS user templates PVC: 5Gi
DFIR-IRIS server data PVC: 20Gi
```

Expected declared PVC total for Wazuh + Shuffle + DFIR-IRIS:

```text
435Gi
```

### `patches/clusterip-services.yaml`

This is the VPN-only safety patch.

The official upstream manifests use public-style `LoadBalancer` services in some
places. This patch changes Wazuh services to:

```text
ClusterIP
```

That means Kubernetes will not create a public AWS load balancer for:

- Wazuh dashboard.
- Wazuh manager API/enrollment.
- Wazuh workers.
- Wazuh indexer.

This helps satisfy:

```text
Ensure Wazuh dashboard is accessible only via VPN, not publicly exposed.
```

Important: `ClusterIP` also means users and laptops outside the cluster cannot reach
Wazuh unless there is a private network path. For real testing, use one of these:

- AWS Client VPN into the VPC.
- Site-to-site VPN into the VPC.
- Bastion host with port-forwarding.
- Internal ALB/NLB reachable only from VPN/private CIDRs.

### `patches/production-resources.yaml`

This sets CPU, memory, and disk sizing.

Current rendered workload shape:

| Component | Replicas | Request per pod | Limit per pod | PVC |
|---|---:|---:|---:|---:|
| Wazuh indexer | 3 | 500m CPU, 1Gi RAM | 1 CPU, 2Gi RAM | 50Gi each |
| Wazuh manager master | 1 | 1 CPU, 1Gi RAM | 2 CPU, 2Gi RAM | 50Gi |
| Wazuh manager worker | 2 | 1 CPU, 1Gi RAM | 2 CPU, 2Gi RAM | 50Gi each |
| Wazuh dashboard | 1 | 500m CPU, 1Gi RAM | 1 CPU, 2Gi RAM | none |

For an AWS test cluster running the full stack, use at least:

```text
3 worker nodes
Recommended instance size: m6i.2xlarge, m6a.2xlarge, or similar
Minimum usable shape: 8 vCPU and 32Gi RAM per node
Storage: at least 500Gi gp3 total for declared PVCs and working headroom
```

For a more comfortable demo to leadership:

```text
3 worker nodes
Recommended instance size: m6i.2xlarge or m6a.2xlarge
Storage: 700Gi gp3 budget allowance
```

### `patches/delete-default-secrets.yaml`

The official upstream Wazuh manifests include example Kubernetes Secrets.

That is not acceptable for a production-grade or boss-facing setup, so this patch
removes those example Secrets. The real secrets come from encrypted SealedSecrets.

### `secrets/sealed/`

This folder receives generated encrypted SealedSecrets.

At first, it is empty except for its own `kustomization.yaml` and README. After the
GitHub Actions workflow runs, this folder should contain encrypted YAML files like:

```text
wazuh-api-cred.yaml
wazuh-authd-pass.yaml
wazuh-cluster-key.yaml
dashboard-cred.yaml
indexer-cred.yaml
```

These are safe to commit because they are encrypted for your cluster's SealedSecrets
controller.

### `.github/workflows/generate-wazuh-sealed-secrets.yml`

This is the automation that generates encrypted secrets.

It reads plaintext values from GitHub Actions secrets, runs the sealing script, and
opens a pull request with encrypted SealedSecrets.

Plaintext values are not committed.

### `scripts/seal-wazuh-secrets.sh`

This script creates temporary Kubernetes Secret YAML locally inside a temp directory,
passes it to `kubeseal`, and writes encrypted SealedSecret YAML.

It requires these inputs:

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

For GitHub Actions, these are GitHub Actions secrets.

For local testing only, copy `.env.example` to `.env`, fill it, and run:

```bash
set -a
. ./.env
set +a
bash scripts/seal-wazuh-secrets.sh
```

Never commit `.env`.

### `agent-groups/windows-endpoints-agent.conf`

This is the group config for the 8 TUROG Windows laptops.

It collects:

```text
Microsoft-Windows-Windows Defender/Operational
Microsoft-Windows-Sysmon/Operational
```

This is how Microsoft Defender events get into Wazuh.

### `agent-groups/suricata-endpoints-agent.conf`

This is the group config for Linux Suricata sensors.

It collects:

```text
/var/log/suricata/eve.json
```

This matters only for Linux hosts that actually run Suricata.

### `patches/agent-group-bootstrap.yaml`

This patch adds an init container to the Wazuh manager master.

When the manager starts, the init container writes:

```text
/var/ossec/etc/shared/windows-endpoints/agent.conf
/var/ossec/etc/shared/suricata-endpoints/agent.conf
```

That is important because Wazuh pushes group files from:

```text
/var/ossec/etc/shared/<GROUP_NAME>/agent.conf
```

to agents in that group.

This satisfies:

```text
Set up group configuration so settings push to all endpoints automatically.
```

### `integrations/manager-integrations.xml`

This file documents the Wazuh-to-Shuffle integration that is applied in
`upstream/wazuh_managers/wazuh_conf/master.conf`.

The repo uses a custom Wazuh integration named `custom-shuffle-secret`. It avoids
putting the Shuffle webhook URL directly in `ossec.conf`. Instead, the script reads
the URL from a mounted Kubernetes Secret named `wazuh-shuffle-webhook`.

The design is:

```text
Wazuh sends alerts to Shuffle
Shuffle enriches with AlienVault OTX
Shuffle creates alerts/cases in DFIR-IRIS
```

### `clusters/testing/aws/shuffle/`

This deploys self-hosted Shuffle.

Files:

- `namespace.yaml` creates the `shuffle` namespace.
- `configmap.yaml` holds non-secret Shuffle settings.
- `serviceaccount.yaml` creates the service account used by Orborus.
- `rbac.yaml` allows Orborus to create workflow execution pods/jobs in the `shuffle` namespace.
- `opensearch.yaml` deploys Shuffle's OpenSearch database.
- `backend.yaml` deploys the Shuffle backend API.
- `frontend.yaml` deploys the Shuffle UI.
- `orborus.yaml` deploys Orborus, the component that runs workflow executions.
- `secrets/sealed/` receives encrypted Shuffle secrets.

All Shuffle services are `ClusterIP`, so Shuffle is private by default. Expose the
Shuffle UI only through VPN/private ingress.

### `clusters/testing/aws/dfir-iris/`

This deploys DFIR-IRIS for case management.

Files:

- `namespace.yaml` creates the `dfir-iris` namespace.
- `configmap.yaml` holds non-secret IRIS settings.
- `postgres.yaml` deploys the IRIS PostgreSQL database.
- `rabbitmq.yaml` deploys RabbitMQ for IRIS background jobs.
- `app.yaml` deploys the IRIS web application.
- `worker.yaml` deploys the IRIS background worker.
- `secrets/sealed/` receives encrypted DFIR-IRIS secrets.

All DFIR-IRIS services are `ClusterIP`, so IRIS is private by default. Expose the
IRIS UI only through VPN/private ingress.

## AWS EKS Test Cluster Design

For the test environment, use AWS EKS.

Minimum practical setup:

```text
Kubernetes: supported EKS version approved by your organization
Worker nodes: 3 nodes
Instance type: m6i.2xlarge or m6a.2xlarge
Storage driver: AWS EBS CSI driver
Storage class: wazuh-storage using encrypted gp3
Network: private subnets preferred
Access: VPN or private bastion
Public Wazuh/Shuffle/DFIR-IRIS exposure: none
```

Recommended demo setup:

```text
Worker nodes: 3 nodes
Instance type: m6i.2xlarge or m6a.2xlarge
Storage allowance: 700Gi gp3
Ingress: internal only
Wazuh dashboard access: VPN only
Shuffle UI access: VPN only
DFIR-IRIS UI access: VPN only
Agent access: VPN/private path only
```

Required EKS add-ons:

```text
Amazon VPC CNI
CoreDNS
kube-proxy
Amazon EBS CSI driver
```

Optional but useful:

```text
AWS Load Balancer Controller, if using internal ALB/NLB
ExternalDNS, if managing private Route 53 records
cert-manager, if issuing TLS certificates through Kubernetes
```

## Network Design

There are two kinds of access:

1. Human access to the dashboard.
2. Agent access from laptops to the Wazuh manager.

### Dashboard Access

The dashboard must not be public.

Current repo setting:

```text
dashboard service = ClusterIP
```

That means there is no public AWS load balancer for the dashboard.

Recommended access choices:

| Option | Use case |
|---|---|
| AWS Client VPN + internal ingress | Best for normal team access |
| Site-to-site VPN + internal ingress | Best if the office network already has VPN to AWS |
| Bastion + kubectl port-forward | Good for testing, not ideal for daily SOC use |

### Agent Access

The 8 Windows laptops need to reach Wazuh on:

```text
1514/TCP - agent events
1515/TCP - agent enrollment
```

The Wazuh dashboard/API also uses:

```text
55000/TCP - Wazuh API
443/TCP or 5601/TCP - dashboard path, depending on ingress design
```

Because services are `ClusterIP`, laptops cannot connect directly from the internet.
For enrollment, provide a private path:

- Laptop connects to VPN.
- VPN can route to an internal Wazuh endpoint.
- Internal endpoint forwards to Wazuh manager services.

For a simple test, a bastion and port-forward can prove the dashboard works, but it
is not enough for all endpoint agents. For all 8 laptops, use VPN/private endpoint
access.

## SealedSecrets Setup

The SealedSecrets controller has a private key inside the cluster and a public
certificate that we use to encrypt secrets.

The safe flow is:

```text
Install SealedSecrets controller
  -> get public certificate
  -> store public certificate in GitHub Actions secret
  -> store Wazuh, Shuffle, and DFIR-IRIS secret inputs in GitHub Actions secrets
  -> run workflow
  -> commit encrypted SealedSecrets
  -> Flux applies them
  -> controller creates real Kubernetes Secrets
```

GitHub Actions secrets to create:

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

Optional GitHub Actions secret after the Shuffle workflow exists:

```text
SHUFFLE_WEBHOOK_URL
```

Recommended values:

```text
WAZUH_API_USERNAME=wazuh-wui
WAZUH_API_PASSWORD=<long random password>
WAZUH_AUTHD_PASS=<long random enrollment password>
WAZUH_CLUSTER_KEY=<32+ character random shared key>
DASHBOARD_USERNAME=kibanaserver
DASHBOARD_PASSWORD=<long random password>
INDEXER_USERNAME=admin
INDEXER_PASSWORD=<long random password>
SHUFFLE_OPENSEARCH_PASSWORD=<long random password>
SHUFFLE_ENCRYPTION_MODIFIER=<long random secret string>
SHUFFLE_DEFAULT_USERNAME=soc-admin
SHUFFLE_DEFAULT_PASSWORD=<long random password>
SHUFFLE_DEFAULT_APIKEY=<long random API key>
DFIR_IRIS_POSTGRES_PASSWORD=<long random database password>
DFIR_IRIS_POSTGRES_ADMIN_USER=raptor
DFIR_IRIS_POSTGRES_ADMIN_PASSWORD=<long random database admin password>
DFIR_IRIS_SECRET_KEY=<long random secret string>
DFIR_IRIS_SECURITY_PASSWORD_SALT=<long random salt>
DFIR_IRIS_ADMIN_PASSWORD=<long random password>
DFIR_IRIS_ADMIN_API_KEY=<long random API key>
```

## Shuffle, DFIR-IRIS, And AlienVault OTX

This is the part that can be confusing, so here is the plain version.

Wazuh does not need to talk directly to DFIR-IRIS or AlienVault OTX.

Wazuh only needs to send alerts to Shuffle.

Shuffle then becomes the automation brain:

```text
Wazuh alert enters Shuffle
  -> Shuffle extracts IPs, domains, URLs, hashes, username, hostname, rule ID, severity
  -> Shuffle asks AlienVault OTX whether indicators are suspicious
  -> Shuffle creates an alert or case in DFIR-IRIS
  -> SOC analyst works the case in DFIR-IRIS
```

### How To Set Up Shuffle

Shuffle can be self-hosted or cloud-hosted. This repo now includes a self-hosted
Shuffle deployment at:

```text
clusters/testing/aws/shuffle
```

Flux should apply it after SealedSecrets and after the shared AWS storage class exists.

Basic setup:

1. Deploy `clusters/testing/aws/shuffle`.
2. Access Shuffle through VPN/private ingress.
3. Log in with the seeded admin credentials if the running Shuffle version accepts
   them. If Shuffle asks for first-admin setup, create the admin user there and store
   the final credentials in the team password vault.
4. Go to `Workflows`.
5. Create a workflow named `Wazuh Alert Triage`.
6. Add a `Webhook` trigger.
7. Copy the webhook URL.
8. Start or enable the webhook trigger.
9. Save the workflow.
10. Add the webhook URL as the GitHub Actions secret `SHUFFLE_WEBHOOK_URL`.
11. Run the `Generate SOC Platform SealedSecrets` workflow again.
12. Merge the generated PR so Flux creates the `wazuh-shuffle-webhook` Secret.

The webhook URL is the value Wazuh needs.

It looks like:

```text
https://<shuffle-host>/api/v1/hooks/<webhook-id>
```

Because Wazuh and Shuffle both run inside Kubernetes, prefer an internal URL for the
GitHub Actions secret when possible:

```text
http://shuffle-backend.shuffle.svc.cluster.local:5001/api/v1/hooks/<webhook-id>
```

Treat this URL like a secret. Anyone with the URL may be able to send data into the
workflow.

### How Wazuh Sends Alerts To Shuffle

Wazuh uses the Integrator module.

The production-safe config shape used by this repo is:

```xml
<integration>
  <name>custom-shuffle-secret</name>
  <hook_url>secret-mounted-at-runtime</hook_url>
  <level>7</level>
  <alert_format>json</alert_format>
</integration>
```

The helper script lives at:

```text
clusters/production/wazuh/integrations/custom-shuffle-secret
```

The script is copied into the Wazuh manager by `patches/agent-group-bootstrap.yaml`.
It reads the real webhook URL from:

```text
/var/ossec/secrets/shuffle-webhook/hook_url
```

That file comes from the optional SealedSecret generated when `SHUFFLE_WEBHOOK_URL`
exists in GitHub Actions secrets.

For the current boss demo, explain it this way:

```text
Wazuh alert forwarding is automated, but the webhook URL remains protected. Git only
contains encrypted SealedSecret YAML, not the plaintext Shuffle webhook.
```

### How To Set Up AlienVault OTX

AlienVault OTX is used for threat intelligence enrichment.

Setup:

1. Create or log in to an OTX account.
2. Go to the OTX settings page.
3. Copy the API key.
4. Store it in Shuffle's secret store as `OTX_API_KEY`.
5. In the Shuffle workflow, add an OTX app action or HTTP request action.
6. Use the Wazuh alert fields as input indicators.

Common indicator types:

```text
IP address
domain
URL
file hash
```

If using a generic HTTP action, the OTX API key is commonly sent with:

```text
X-OTX-API-KEY: <OTX_API_KEY>
```

### How To Set Up DFIR-IRIS

DFIR-IRIS is the case management system.

DFIR-IRIS replaces TheHive in this design because the current requirement is an
open-source case management path without a commercial-trial dependency.

This repo now includes a self-hosted DFIR-IRIS deployment at:

```text
clusters/testing/aws/dfir-iris
```

Setup:

1. Deploy `clusters/testing/aws/dfir-iris`.
2. Access DFIR-IRIS through VPN/private ingress.
3. Log in with the administrator credentials provided through SealedSecrets.
4. Create a case template for Wazuh alerts if desired.
5. Create a service account/user for Shuffle, for example `shuffle-wazuh`.
6. Give it only the permissions needed to create alerts/cases and observables.
7. Generate or copy the API key for that user.
8. Store these values in Shuffle's secret store:

```text
DFIR_IRIS_URL
DFIR_IRIS_API_KEY
```

DFIR-IRIS exposes an API that Shuffle can call with the IRIS API key.

In Shuffle:

1. Add an HTTP request action or DFIR-IRIS-compatible app action if available.
2. Create a DFIR-IRIS alert or case when a Wazuh alert is high enough priority.
3. Add observables such as source IP, destination IP, domain, URL, username, hostname,
   and file hash.
4. If OTX says an indicator is suspicious, raise severity or create a case.

Suggested logic:

```text
If Wazuh rule level >= 7:
  create DFIR-IRIS alert

If OTX finds malicious indicator:
  set DFIR-IRIS severity to High
  add OTX pulse/context as an observable or alert detail

If Wazuh rule level >= 12:
  create DFIR-IRIS case immediately
```

## Microsoft Defender Integration

Microsoft Defender is not configured in the Wazuh manager directly.

It is configured in the Windows agent group:

```text
clusters/production/wazuh/agent-groups/windows-endpoints-agent.conf
```

That file tells all Windows endpoints in the `windows-endpoints` group to collect:

```text
Microsoft-Windows-Windows Defender/Operational
Microsoft-Windows-Sysmon/Operational
```

Because `patches/agent-group-bootstrap.yaml` writes this file into the Wazuh manager's
shared group folder, the config is pushed automatically to agents in that group.

## Suricata Integration

Suricata is configured through a Linux agent group:

```text
clusters/production/wazuh/agent-groups/suricata-endpoints-agent.conf
```

That file tells Suricata sensors to collect:

```text
/var/log/suricata/eve.json
```

This does not affect the 8 Windows laptops. It is for Linux hosts running Suricata.

## Enrolling The 8 TUROG Windows Laptops

The Kubernetes deployment does not magically install software on laptops. The Wazuh
agent still needs to be installed on each laptop.

Recommended rollout method:

```text
Microsoft Intune, GPO, RMM, or scripted PowerShell deployment
```

Each Windows laptop should be installed with:

```text
Manager address: private Wazuh manager endpoint reachable over VPN
Enrollment group: windows-endpoints
Enrollment password: WAZUH_AUTHD_PASS
```

The endpoint group must exist before enrollment. This repo creates the group folder
and `agent.conf` through the Wazuh manager bootstrap.

Agent config concept:

```xml
<client>
  <server>
    <address>wazuh.internal.turog.example</address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
  <enrollment>
    <groups>windows-endpoints</groups>
  </enrollment>
</client>
```

For the 8 TUROG laptops, track them like this:

| Laptop | Expected group | Status |
|---|---|---|
| TUROG-WIN-01 | windows-endpoints | To enroll |
| TUROG-WIN-02 | windows-endpoints | To enroll |
| TUROG-WIN-03 | windows-endpoints | To enroll |
| TUROG-WIN-04 | windows-endpoints | To enroll |
| TUROG-WIN-05 | windows-endpoints | To enroll |
| TUROG-WIN-06 | windows-endpoints | To enroll |
| TUROG-WIN-07 | windows-endpoints | To enroll |
| TUROG-WIN-08 | windows-endpoints | To enroll |

Success criteria:

```text
All 8 laptops show Active in Wazuh dashboard.
All 8 laptops belong to windows-endpoints.
All 8 laptops show synced group configuration.
Windows Defender events appear in Wazuh.
Sysmon events appear in Wazuh if Sysmon is installed.
```

## Full Deployment Flow

Use this order:

1. Build AWS EKS cluster.
2. Install required EKS add-ons, especially AWS EBS CSI driver.
3. Install FluxCD and connect Flux to this Git repository.
4. Configure Flux to apply `clusters/testing/aws/sealed-secrets`.
5. Wait for SealedSecrets controller to be ready.
6. Get the SealedSecrets public certificate.
7. Add all required GitHub Actions secrets.
8. Run `Generate SOC Platform SealedSecrets`.
9. Review and merge the generated PR.
10. Configure Flux to apply `clusters/testing/aws/wazuh`.
11. Wait for Wazuh pods and PVCs to become ready.
12. Configure Flux to apply `clusters/testing/aws/shuffle`.
13. Wait for Shuffle frontend, backend, Orborus, and OpenSearch to become ready.
14. Configure Flux to apply `clusters/testing/aws/dfir-iris`.
15. Wait for DFIR-IRIS app, worker, PostgreSQL, and RabbitMQ to become ready.
16. Confirm Wazuh, Shuffle, and DFIR-IRIS services are `ClusterIP`.
17. Configure VPN/private access to Wazuh dashboard, Shuffle UI, and DFIR-IRIS UI.
18. Configure VPN/private agent path to ports `1514/TCP` and `1515/TCP`.
19. Set up Shuffle workflow webhook.
20. Store OTX and DFIR-IRIS credentials in Shuffle.
21. Configure Wazuh-to-Shuffle webhook securely.
22. Enroll all 8 TUROG Windows laptops into `windows-endpoints`.
23. Verify group config sync.
24. Verify Defender events, Wazuh alerts, Shuffle executions, OTX enrichment, and DFIR-IRIS alerts/cases.

## Verification Checklist

### Cluster

```text
EKS cluster exists.
AWS EBS CSI driver exists.
Flux is reconciled.
SealedSecrets controller is running.
Wazuh namespace exists.
Wazuh PVCs are bound.
Wazuh pods are running.
```

### Network

```text
No public LoadBalancer for Wazuh dashboard.
No public LoadBalancer for Shuffle UI.
No public LoadBalancer for DFIR-IRIS UI.
Dashboard service is ClusterIP.
Wazuh manager service is ClusterIP.
VPN/private route exists for SOC users.
VPN/private route exists for Windows laptops.
```

### Secrets

```text
No .env committed.
No plaintext Secret YAML committed.
SealedSecret YAML exists for Wazuh credentials.
SealedSecret YAML exists for Shuffle credentials.
SealedSecret YAML exists for DFIR-IRIS credentials.
Optional SealedSecret YAML exists for Wazuh-to-Shuffle webhook after the Shuffle workflow is created.
Kubernetes Secret objects are created by SealedSecrets controller.
Indexer password matches internal_users.yml bcrypt hash.
Dashboard service password matches internal_users.yml bcrypt hash.
```

### Endpoint Enrollment

```text
8 TUROG Windows laptops installed with Wazuh agent.
8 TUROG Windows laptops enrolled into windows-endpoints.
8 TUROG Windows laptops show Active.
8 TUROG Windows laptops show group_config_status synced.
Windows Defender events visible.
```

### Integrations

```text
Shuffle workflow exists.
Shuffle webhook is active.
Wazuh can send alerts to Shuffle.
OTX API key stored in Shuffle.
DFIR-IRIS API key stored in Shuffle.
Shuffle creates DFIR-IRIS alert/case from Wazuh alert.
```

## Risks And Design Notes

- The dashboard is not public because services are patched to `ClusterIP`.
- A private ingress or VPN path is still required for real users.
- Endpoint enrollment needs private access to Wazuh manager ports.
- The real Shuffle webhook URL should not be committed to Git.
- DFIR-IRIS and OTX API keys should live in Shuffle or a secret manager, not Wazuh ConfigMaps.
- The current repo deploys Wazuh, SealedSecrets, Shuffle, and DFIR-IRIS.
- The current repo configures Microsoft Defender and Suricata collection through Wazuh agent groups.
- The included Shuffle Kubernetes manifests are suitable for AWS testing. Before
  final production, pin tested Shuffle image tags instead of `latest` and decide on
  the backup/restore and scaling model.
- DFIR-IRIS is pinned to `v2.4.27` because both the app and database image tags are
  published. Review DFIR-IRIS release notes before upgrading.
- Back up Wazuh indexer data, Shuffle OpenSearch data, and DFIR-IRIS PostgreSQL data
  before any production handoff.

## References

- Official Wazuh Kubernetes deployment: `https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/kubernetes-deployment.html`
- Wazuh external integrations: `https://documentation.wazuh.com/current/user-manual/manager/integration-with-external-apis.html`
- Wazuh centralized agent configuration: `https://documentation.wazuh.com/current/user-manual/reference/centralized-configuration.html`
- Wazuh Windows enrollment groups: `https://documentation.wazuh.com/current/user-manual/agent/agent-enrollment/enrollment-methods/via-agent-configuration/windows-endpoint.html`
- Shuffle self-hosted install guide: `https://github.com/Shuffle/Shuffle/blob/main/.github/install-guide.md`
- AWS EBS CSI driver for EKS: `https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html`
- DFIR-IRIS documentation: `https://docs.dfir-iris.org/`
- DFIR-IRIS container images: `https://github.com/dfir-iris/iris-web/pkgs/container/iriswebapp_app`
- AlienVault OTX API SDK reference: `https://github.com/AlienVault-OTX/OTX-Python-SDK`
