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
- The Wazuh dashboard is exposed using a `LoadBalancer` service.

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
