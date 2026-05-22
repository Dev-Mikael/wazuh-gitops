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
: "${SHUFFLE_OPENSEARCH_PASSWORD:?Set SHUFFLE_OPENSEARCH_PASSWORD.}"
: "${SHUFFLE_ENCRYPTION_MODIFIER:?Set SHUFFLE_ENCRYPTION_MODIFIER.}"
: "${SHUFFLE_DEFAULT_USERNAME:?Set SHUFFLE_DEFAULT_USERNAME.}"
: "${SHUFFLE_DEFAULT_PASSWORD:?Set SHUFFLE_DEFAULT_PASSWORD.}"
: "${SHUFFLE_DEFAULT_APIKEY:?Set SHUFFLE_DEFAULT_APIKEY.}"
: "${DFIR_IRIS_POSTGRES_PASSWORD:?Set DFIR_IRIS_POSTGRES_PASSWORD.}"
: "${DFIR_IRIS_POSTGRES_ADMIN_USER:?Set DFIR_IRIS_POSTGRES_ADMIN_USER.}"
: "${DFIR_IRIS_POSTGRES_ADMIN_PASSWORD:?Set DFIR_IRIS_POSTGRES_ADMIN_PASSWORD.}"
: "${DFIR_IRIS_SECRET_KEY:?Set DFIR_IRIS_SECRET_KEY.}"
: "${DFIR_IRIS_SECURITY_PASSWORD_SALT:?Set DFIR_IRIS_SECURITY_PASSWORD_SALT.}"
: "${DFIR_IRIS_ADMIN_PASSWORD:?Set DFIR_IRIS_ADMIN_PASSWORD.}"
: "${DFIR_IRIS_ADMIN_API_KEY:?Set DFIR_IRIS_ADMIN_API_KEY.}"

wazuh_out_dir="${1:-clusters/production/wazuh/secrets/sealed}"
shuffle_out_dir="${SHUFFLE_SECRETS_OUT_DIR:-clusters/testing/aws/shuffle/secrets/sealed}"
dfir_iris_out_dir="${DFIR_IRIS_SECRETS_OUT_DIR:-clusters/testing/aws/dfir-iris/secrets/sealed}"
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

mkdir -p "$wazuh_out_dir" "$shuffle_out_dir" "$dfir_iris_out_dir"

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

if [[ -n "${SHUFFLE_WEBHOOK_URL:-}" && "$SHUFFLE_WEBHOOK_URL" != *replace-me* ]]; then
  seal_secret "$wazuh_out_dir" wazuh wazuh-shuffle-webhook \
    --from-literal="hook_url=$SHUFFLE_WEBHOOK_URL"
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

if [[ -n "${SHUFFLE_WEBHOOK_URL:-}" && "$SHUFFLE_WEBHOOK_URL" != *replace-me* ]]; then
  printf '  - wazuh-shuffle-webhook.yaml\n' >> "$wazuh_out_dir/kustomization.yaml"
fi

seal_secret "$shuffle_out_dir" shuffle shuffle-secrets \
  --from-literal="OPENSEARCH_INITIAL_ADMIN_PASSWORD=$SHUFFLE_OPENSEARCH_PASSWORD" \
  --from-literal="SHUFFLE_OPENSEARCH_PASSWORD=$SHUFFLE_OPENSEARCH_PASSWORD" \
  --from-literal="SHUFFLE_ENCRYPTION_MODIFIER=$SHUFFLE_ENCRYPTION_MODIFIER" \
  --from-literal="SHUFFLE_DEFAULT_USERNAME=$SHUFFLE_DEFAULT_USERNAME" \
  --from-literal="SHUFFLE_DEFAULT_PASSWORD=$SHUFFLE_DEFAULT_PASSWORD" \
  --from-literal="SHUFFLE_DEFAULT_APIKEY=$SHUFFLE_DEFAULT_APIKEY"

cat > "$shuffle_out_dir/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - shuffle-secrets.yaml
EOF

seal_secret "$dfir_iris_out_dir" dfir-iris dfir-iris-secrets \
  --from-literal="POSTGRES_PASSWORD=$DFIR_IRIS_POSTGRES_PASSWORD" \
  --from-literal="POSTGRES_ADMIN_USER=$DFIR_IRIS_POSTGRES_ADMIN_USER" \
  --from-literal="POSTGRES_ADMIN_PASSWORD=$DFIR_IRIS_POSTGRES_ADMIN_PASSWORD" \
  --from-literal="IRIS_SECRET_KEY=$DFIR_IRIS_SECRET_KEY" \
  --from-literal="IRIS_SECURITY_PASSWORD_SALT=$DFIR_IRIS_SECURITY_PASSWORD_SALT" \
  --from-literal="IRIS_ADM_PASSWORD=$DFIR_IRIS_ADMIN_PASSWORD" \
  --from-literal="IRIS_ADM_API_KEY=$DFIR_IRIS_ADMIN_API_KEY"

cat > "$dfir_iris_out_dir/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - dfir-iris-secrets.yaml
EOF

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
echo "Generated sealed Shuffle secrets in $shuffle_out_dir"
echo "Generated sealed DFIR-IRIS secrets in $dfir_iris_out_dir"
