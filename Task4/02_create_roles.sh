#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace sales   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenants --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace finance --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace data    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-configurer
rules:
  - apiGroups: ["", "apps", "batch", "networking.k8s.io"]
    resources:
      # core
      - pods
      - pods/log
      - services
      - endpoints
      - configmaps
      - secrets
      - persistentvolumeclaims
      # apps
      - deployments
      - daemonsets
      - statefulsets
      - replicasets
      # batch
      - jobs
      - cronjobs
      # networking
      - ingresses
    verbs: ["get","list","watch","create","update","patch","delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get","list","watch"]
EOF

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secrets-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get","list","watch"]
EOF

echo "OK"
