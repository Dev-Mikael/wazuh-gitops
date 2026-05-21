# Wazuh Azure Installation

These manifests install Wazuh into a dedicated `wazuh` namespace on a Kubernetes cluster running in Azure.

## Files

- `namespace.yaml` - Creates the `wazuh` namespace.
- `helm-repository.yaml` - Adds the Wazuh Helm chart source for Flux.
- `helm-release.yaml` - Deploys the Wazuh Helm chart into the `wazuh` namespace.
- `values.yaml` - Helm values overrides for Azure.
- `wazuh-values-configmap.yaml` - Flux ConfigMap containing the Helm values for the release.

## Prerequisites

- Azure Kubernetes Service (AKS) or Azure-hosted Kubernetes cluster.
- Cluster already running and accessible via `kubectl`.
- Flux v2 installed and configured, or the ability to apply raw Kubernetes manifests.

## Install with Flux

Apply the folder manifests in your Flux-enabled git repo path or directly via `kubectl` if your cluster is already synced by Flux.

```bash
kubectl apply -f clusters/production/wazuh/namespace.yaml
kubectl apply -f clusters/production/wazuh/helm-repository.yaml
kubectl apply -f clusters/production/wazuh/wazuh-values-configmap.yaml
kubectl apply -f clusters/production/wazuh/helm-release.yaml
```

## Manual Helm install

If you want to install Wazuh manually with Helm instead of Flux:

```bash
helm repo add wazuh https://packages.wazuh.com/4.x/helm
helm repo update
kubectl create namespace wazuh
helm install wazuh wazuh/wazuh -n wazuh -f clusters/production/wazuh/values.yaml
```

## Azure-specific notes

- `storageClassName: default` is configured to use the cluster default storage class on AKS.
- If your Azure cluster requires a named storage class, change the value to `managed-premium` or `managed-standard`.
- This manifest does not configure a public domain name or DNS record.
- The Wazuh dashboard is configured as `ClusterIP`, so it is not directly exposed as a public Azure LoadBalancer.

## Domain-only dashboard access

This manifest does not create DNS records or an ingress resource automatically.

For access over VPN or a bastion host, keep `dashboard.service.type: ClusterIP` and use one of these approaches:

### Option 1: Internal ingress behind VPN

- Use your existing ingress controller with an internal-facing load balancer or host.
- Create an `Ingress` for a private host such as `wazuh.internal.example.com`.
- Configure DNS so the host resolves only inside the VPN or corporate network.
- Restrict access at the ingress controller with source IP filtering or firewall rules.
- Use TLS for secure traffic.

This gives you a real domain name for the dashboard while avoiding public internet exposure.

### Option 2: Bastion host / jumpbox access

If you prefer not to expose the dashboard by DNS at all, access it through a bastion host:

1. SSH into your bastion host on the private network.
2. From the bastion, use `kubectl` to connect to the cluster.
3. Forward the dashboard port locally:

```bash
ssh -L 5601:localhost:5601 <bastion-host>
```

4. On the bastion, run:

```bash
kubectl port-forward -n wazuh svc/wazuh-dashboard 5601:5601
```

5. Open `http://localhost:5601` from your local machine.

If the service name differs in your Wazuh deployment, use the actual dashboard service name from `kubectl get svc -n wazuh`.

### Recommended setup

- Use `ClusterIP` for the dashboard service.
- Use an internal ingress host or private DNS for VPN-only access.
- Do not expose the dashboard on a public LoadBalancer unless you explicitly need it.

## GitOps / Flux usage

- If you are using Flux, add this directory to a `Kustomization` or `HelmRelease` path in your Flux configuration.
- The namespace, Helm repository, ConfigMap, and Helm release should be applied together in the same repo path.
- Because `helm-release.yaml` lives in the `wazuh` namespace, Flux will install the Wazuh chart into that same namespace.

## Admin credentials

Wazuh dashboard credentials are generally created during deployment and stored in a Kubernetes Secret.

1. Find the dashboard-related secret in the `wazuh` namespace:

```bash
kubectl get secret -n wazuh
```

2. Look for a secret name containing `dashboard` or `wazuh-dashboard`.

3. Decode the secret data for the admin password:

```bash
kubectl get secret <secret-name> -n wazuh -o jsonpath="{.data.admin-password}" | base64 --decode
```

4. The dashboard admin username is typically `admin`.

If the secret key is different, inspect the secret contents:

```bash
kubectl get secret <secret-name> -n wazuh -o yaml
```

## Customization

- Update `values.yaml` for CPU/memory, replica count, or storage sizes.
- If you need internal dashboard access only, change `dashboard.service.type` to `ClusterIP` or use an ingress controller.
- If using Flux, keep `helm-release.yaml`, `helm-repository.yaml`, and `wazuh-values-configmap.yaml` together in the same repo path.
