#!/usr/bin/env bash
set -euo pipefail

: "${KUBESEAL_CERT:?Set KUBESEAL_CERT to the SealedSecrets public certificate path.}"
: "${WAZUH_API_USERNAME:?Set WAZUH_API_USERNAME.}"
: "${WAZUH_API_PASSWORD:?Set WAZUH_API_PASSWORD.}"
: "${WAZUH_AUTHD_PASS:?Set WAZUH_AUTHD_PASS.}"
: "${WAZUH_CLUSTER_KEY:?Set WAZUH_CLUSTER_KEY.}"
: "${DASHBOARD_USERNAME:?Set DASHBOARD_USERNAME.}"
: "${DASHBOARD_PASSWORD:?Set DASHBOARD_PASSWORD.}"
: "${INDEXER_USERNAME:?Set INDEXER_USERNAME.}"
: "${INDEXER_PASSWORD:?Set INDEXER_PASSWORD.}"

wazuh_out_dir="${1:-clusters/production/wazuh/secrets/sealed}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

seal_secret() {
  local out_dir="$1"
  local namespace="$2"
  local name="$3"
  local from_literal_args=("${@:4}")

  kubectl create secret generic "$name" \
    --namespace "$namespace" \
    "${from_literal_args[@]}" \
    --dry-run=client \
    --output yaml > "$tmp_dir/$name.yaml"

  kubeseal \
    --cert "$KUBESEAL_CERT" \
    --format yaml \
    < "$tmp_dir/$name.yaml" \
    > "$out_dir/$name.yaml"
}

mkdir -p "$wazuh_out_dir"

seal_secret "$wazuh_out_dir" wazuh wazuh-api-cred \
  --from-literal="username=$WAZUH_API_USERNAME" \
  --from-literal="password=$WAZUH_API_PASSWORD"

seal_secret "$wazuh_out_dir" wazuh wazuh-authd-pass \
  --from-literal="authd.pass=$WAZUH_AUTHD_PASS"

seal_secret "$wazuh_out_dir" wazuh wazuh-cluster-key \
  --from-literal="key=$WAZUH_CLUSTER_KEY"

seal_secret "$wazuh_out_dir" wazuh dashboard-cred \
  --from-literal="username=$DASHBOARD_USERNAME" \
  --from-literal="password=$DASHBOARD_PASSWORD"

seal_secret "$wazuh_out_dir" wazuh indexer-cred \
  --from-literal="username=$INDEXER_USERNAME" \
  --from-literal="password=$INDEXER_PASSWORD"

if [[ -n "${OTX_API_KEY:-}" && "$OTX_API_KEY" != *replace-* ]]; then
  seal_secret "$wazuh_out_dir" wazuh wazuh-otx-api-key \
    --from-literal="api_key=$OTX_API_KEY"
fi

cat > "$wazuh_out_dir/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - wazuh-api-cred.yaml
  - wazuh-authd-pass.yaml
  - wazuh-cluster-key.yaml
  - dashboard-cred.yaml
  - indexer-cred.yaml
EOF

if [[ -n "${OTX_API_KEY:-}" && "$OTX_API_KEY" != *replace-* ]]; then
  printf '  - wazuh-otx-api-key.yaml\n' >> "$wazuh_out_dir/kustomization.yaml"
fi

python3 - <<'PY'
import os
from pathlib import Path

import bcrypt

path = Path("clusters/production/wazuh/upstream/indexer_stack/wazuh-indexer/indexer_conf/internal_users.yml")
text = path.read_text()

admin_hash = bcrypt.hashpw(os.environ["INDEXER_PASSWORD"].encode(), bcrypt.gensalt(rounds=12)).decode()
dashboard_hash = bcrypt.hashpw(os.environ["DASHBOARD_PASSWORD"].encode(), bcrypt.gensalt(rounds=12)).decode()

def replace_hash(src, user, new_hash):
    marker = f"{user}:\n  hash: "
    start = src.index(marker) + len(marker)
    quote = src[start]
    end = src.index(quote, start + 1)
    return src[:start] + quote + new_hash + src[end:]

text = replace_hash(text, "admin", admin_hash)
text = replace_hash(text, "kibanaserver", dashboard_hash)
path.write_text(text)
PY

echo "Generated sealed Wazuh secrets in $wazuh_out_dir"
if [[ -n "${OTX_API_KEY:-}" && "$OTX_API_KEY" != *replace-* ]]; then
  echo "Generated sealed AlienVault OTX secret in $wazuh_out_dir"
fi
