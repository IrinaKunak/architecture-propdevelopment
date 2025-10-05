#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_ADMIN="${KUBECONFIG:-$HOME/.kube/config}"
OUT_DIR="./kube-users"
CLUSTER_NAME="$(kubectl config view -o jsonpath='{.clusters[0].name}')"
CLUSTER_SERVER="$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')"
CLUSTER_CA="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"

mkdir -p "$OUT_DIR"

create_user() {
  local username="$1"; shift
  local groups=("$@")

  local user_dir="${OUT_DIR}/${username}"
  mkdir -p "$user_dir"

  openssl genrsa -out "${user_dir}/${username}.key" 2048 2>/dev/null

  local subj="/CN=${username}"
  for g in "${groups[@]}"; do
    subj="${subj}/O=${g}"
  done

  openssl req -new -key "${user_dir}/${username}.key" -out "${user_dir}/${username}.csr" -subj "${subj}" 2>/dev/null

  local CSR_NAME="user-${username}"
  kubectl delete csr "${CSR_NAME}" --ignore-not-found

  kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: $(base64 < "${user_dir}/${username}.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

  kubectl certificate approve "${CSR_NAME}"

  local crt_b64
  for i in {1..20}; do
    crt_b64="$(kubectl get csr "${CSR_NAME}" -o jsonpath='{.status.certificate}' || true)"
    if [[ -n "${crt_b64}" ]]; then break; fi
    sleep 1
  done
  if [[ -z "${crt_b64}" ]]; then
    echo "ERROR: certificate not issued for ${username}" >&2
    exit 1
  fi
  echo "${crt_b64}" | base64 -d > "${user_dir}/${username}.crt"

  cat > "${user_dir}/kubeconfig" <<KCFG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${username}
  name: ${username}@${CLUSTER_NAME}
current-context: ${username}@${CLUSTER_NAME}
users:
- name: ${username}
  user:
    client-certificate: ${user_dir}/${username}.crt
    client-key: ${user_dir}/${username}.key
KCFG

  echo "${username}"
}

create_user "alice" "sales-viewers"
create_user "bob"   "tenants-configurers"
create_user "carol" "finance-configurers"
create_user "dave"  "sec-privileged"

echo "Done. Users stored in ${OUT_DIR}/"
