#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
CP_RELEASE="${2:-kong-cp}"
DP_RELEASE="${3:-kong-dp}"

echo "##############################################################"
echo "Deploying Kong Hybrid Mode to namespace: ${NAMESPACE}"
echo "Control Plane release: ${CP_RELEASE}"
echo "Data Plane release: ${DP_RELEASE}"
echo "##############################################################"

# Create namespace if it doesn't exist
echo "Checking if namespace ${NAMESPACE} exists..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# Generate cluster certificate for CP/DP communication
echo "Generating cluster certificate..."
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout /tmp/kong-cluster.key -out /tmp/kong-cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"

# Create or update the TLS secret
echo "Creating cluster certificate secret..."
kubectl create secret tls kong-cluster-cert \
  --cert=/tmp/kong-cluster.crt --key=/tmp/kong-cluster.key \
  -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Clean up temp cert files
rm -f /tmp/kong-cluster.key /tmp/kong-cluster.crt

# Deploy Postgres for Control Plane
echo "=============================================="
echo "Deploying Postgres for Control Plane..."
echo "=============================================="
PG_SERVICE="${CP_RELEASE}-postgresql"

# Create Postgres PVC
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "${PG_SERVICE}"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Create Postgres Deployment
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${PG_SERVICE}"
  labels:
    app: "${PG_SERVICE}"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: "${PG_SERVICE}"
  template:
    metadata:
      labels:
        app: "${PG_SERVICE}"
    spec:
      containers:
      - name: postgres
        image: registry.redhat.io/rhel8/postgresql-13:latest
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRESQL_USER
          value: "kong"
        - name: POSTGRESQL_PASSWORD
          value: "kong"
        - name: POSTGRESQL_DATABASE
          value: "kong"
        volumeMounts:
        - name: data
          mountPath: /var/lib/pgsql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: "${PG_SERVICE}"
EOF

# Create Postgres Service
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Service
metadata:
  name: "${PG_SERVICE}"
  labels:
    app: "${PG_SERVICE}"
spec:
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: "${PG_SERVICE}"
EOF

echo "Waiting for Postgres to be ready..."
kubectl wait --for=condition=available deployment/"${PG_SERVICE}" -n "${NAMESPACE}" --timeout=3m

PG_HOST="${PG_SERVICE}.${NAMESPACE}.svc.cluster.local"

# Add Kong Helm repository
echo "Adding Kong Helm repository..."
helm repo add kong https://charts.konghq.com
helm repo update

# Deploy Control Plane
echo "=============================================="
echo "Deploying Kong Control Plane..."
echo "=============================================="
helm upgrade --install "${CP_RELEASE}" kong/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values_cp.yaml \
  --set env.pg_host="${PG_HOST}" \
  --set env.pg_port="5432" \
  --set env.pg_user="kong" \
  --set env.pg_password="kong" \
  --set env.pg_database="kong" \
  --wait --timeout 5m

# Update SCC policy for CP service account
echo "Updating SCC policy for CP service account..."
oc adm policy add-scc-to-user anyuid -z "${CP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true
oc adm policy add-scc-to-user nonroot-v2 -z "${CP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true

# Build DP cluster_control_plane value
CP_CLUSTER_SVC="${CP_RELEASE}-cluster.${NAMESPACE}.svc.cluster.local:8005"

# Deploy Data Plane
echo "=============================================="
echo "Deploying Kong Data Plane..."
echo "=============================================="
helm upgrade --install "${DP_RELEASE}" kong/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values_dp.yaml \
  --set env.cluster_control_plane="${CP_CLUSTER_SVC}" \
  --wait --timeout 5m

# Update SCC policy for DP service account
echo "Updating SCC policy for DP service account..."
oc adm policy add-scc-to-user anyuid -z "${DP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true
oc adm policy add-scc-to-user nonroot-v2 -z "${DP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true

# Create OpenShift routes
echo "Creating OpenShift routes..."
# Route for CP Kong Manager GUI
oc create route edge kong-cp-manager --service="${CP_RELEASE}-manager" -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo ""
echo "##############################################################"
echo "Kong Hybrid Mode deployed successfully!"
echo "Namespace: ${NAMESPACE}"
echo "Control Plane: ${CP_RELEASE}"
echo "Data Plane: ${DP_RELEASE}"
echo "##############################################################"
echo ""
echo "Control Plane Kong Manager GUI:"
echo "  https://$(oc get route -n "${NAMESPACE}" kong-cp-manager -o jsonpath='{.spec.host}' 2>/dev/null)"
echo ""
echo "To verify CP nodes:"
echo "  curl -sk https://$(oc get route -n "${NAMESPACE}" kong-cp-manager -o jsonpath='{.spec.host}' 2>/dev/null)/api/clustering/data-planes"

