# Kong AI Gateway - Hybrid Mode Deployment (Using Official Helm Chart)

This directory contains configuration files for deploying Kong AI Gateway in **Hybrid Mode** on OpenShift/Kubernetes using the official Kong Helm chart.

Hybrid mode splits Kong into **Control Plane (CP)** nodes (Admin API, database interactions) and **Data Plane (DP)** nodes (proxy traffic). DP nodes receive configuration from CP nodes over a TLS-secured cluster channel.

## Directory Structure

```
ai-gateways/kong/
├── values_cp.yaml           # Control Plane configuration
├── values_dp.yaml           # Data Plane configuration
├── test-connectivity.sh     # Script to verify deployment
└── README.md                # This file
```

## Prerequisites

1. **OpenShift/Kubernetes Cluster**: Access to an OpenShift 4.x+ or Kubernetes 1.21+ cluster
2. **Helm 3.x**: Install Helm following the [official guide](https://helm.sh/docs/intro/install/)
3. **kubectl/oc CLI**: Configured to communicate with your cluster
4. **OpenSSL**: For generating cluster certificates
5. **Namespace**: Create or have access to a target namespace (e.g., `kong`)

## Deployment

### Quick Deploy

Use the provided scripts to deploy and clean up both CP and DP:

```bash
# Deploy
./env_preparation/kong_deploy.sh [namespace] [cp-release-name] [dp-release-name]

# Cleanup
./env_preparation/kong_cleanup.sh [namespace] [cp-release-name] [dp-release-name]
```

Defaults: `namespace=kong`, `cp-release-name=kong-cp`, `dp-release-name=kong-dp`

```bash
# Deploy with defaults
./env_preparation/kong_deploy.sh

# Cleanup with defaults
./env_preparation/kong_cleanup.sh

# Deploy with custom names
./env_preparation/kong_deploy.sh my-namespace my-cp my-dp
```

### Manual Deployment

#### 1. Add Kong Helm Repository

```bash
helm repo add kong https://charts.konghq.com
helm repo update
```

#### 2. Generate Cluster Certificate

Hybrid mode requires a TLS certificate for CP/DP communication:

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout /tmp/cluster.key -out /tmp/cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"

kubectl create secret tls kong-cluster-cert \
  --cert=/tmp/cluster.crt --key=/tmp/cluster.key \
  -n kong
```

#### 3. Deploy Control Plane

```bash
helm install kong-cp kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values_cp.yaml \
  --wait --timeout 5m
```

#### 4. Deploy Data Plane

Determine the CP cluster service address and pass it to the DP:

```bash
helm install kong-dp kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values_dp.yaml \
  --set env.cluster_control_plane="kong-cp-cluster.kong.svc.cluster.local:8005" \
  --wait --timeout 5m
```

#### 5. Create OpenShift Routes

```bash
# CP Admin API
oc create route edge kong-cp-admin --service=kong-cp-admin -n kong

# DP Proxy
oc create route edge kong-dp-proxy --service=kong-dp-proxy -n kong
```

#### 6. Verify Deployment

Check that both CP and DP pods are running and connected:

```bash
# Check pods
oc get pods -n kong

# Check CP clustering status (DP nodes should appear)
curl -s https://$(oc get route kong-cp-admin -n kong -o jsonpath='{.spec.host}')/clustering/data-planes
```

## Architecture

```
                  ┌──────────────────┐
                  │   PostgreSQL     │
                  │   (optional)     │
                  └────────┬─────────┘
                           │
                  ┌────────▼─────────┐
                  │  Control Plane   │
                  │  (Admin API)     │
                  │  Port: 8005/TLS  │
                  └────────┬─────────┘
                           │ cluster sync
          ┌────────────────┼────────────────┐
          │                │                │
  ┌───────▼───────┐ ┌──────▼───────┐ ┌──────▼───────┐
  │  Data Plane   │ │  Data Plane  │ │  Data Plane  │
  │  (Proxy)      │ │  (Proxy)     │ │  (Proxy)     │
  │  Port 80/443  │ │  Port 80/443 │ │  Port 80/443 │
  └───────────────┘ └──────────────┘ └──────────────┘
```

## Configuration Files

### Control Plane (`values_cp.yaml`)

- `env.role: control_plane` - Sets Kong role to CP
- `cluster.enabled: true` - Exposes cluster listen port (8005/TLS)
- `proxy.enabled: false` - CP does not handle proxy traffic
- `admin.enabled: true` - Admin API for configuration
- `secretVolumes: [kong-cluster-cert]` - Mounts the cluster TLS certificate
- `fullnameOverride: "kong-cp"` - Predictable resource naming
- Custom labels (`extraLabels`, `podLabels`) commented out to avoid selector mismatches

### Data Plane (`values_dp.yaml`)

- `env.role: data_plane` - Sets Kong role to DP
- `env.database: "off"` - DP is stateless, receives config from CP
- `env.cluster_control_plane` - Points to the CP cluster service
- `proxy.enabled: true` - DP handles all proxy traffic
- `admin.enabled: false` - Admin API disabled on DP
- `migrations.preUpgrade/postUpgrade: false` - Migrations run on CP only
- `waitImage.enabled: false` - No DB dependency on DP
- `fullnameOverride: "kong-dp"` - Predictable resource naming
- Custom labels (`extraLabels`, `podLabels`) commented out to avoid selector mismatches

## Accessing Kong

### Control Plane Admin API
```
https://<kong-cp-admin-route-host>
```

Use this for configuration, plugin management, and monitoring connected DP nodes.

### Data Plane Proxy
```
https://<kong-dp-proxy-route-host>
```

All AI traffic routes through this endpoint.

## Upgrading

When upgrading Kong versions, always upgrade the **Control Plane first**, then the **Data Plane**:

```bash
# 1. Upgrade CP
helm upgrade kong-cp kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values_cp.yaml \
  --wait --timeout 5m

# 2. Upgrade DP
helm upgrade kong-dp kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values_dp.yaml \
  --set env.cluster_control_plane="kong-cp-cluster.kong.svc.cluster.local:8005" \
  --wait --timeout 5m
```

## Uninstalling

```bash
helm uninstall kong-dp --namespace kong
helm uninstall kong-cp --namespace kong
kubectl delete secret kong-cluster-cert -n kong
# Optionally delete the namespace
oc delete project kong
```

## References

- [Kong Hybrid Mode Documentation](https://docs.konghq.com/gateway/latest/plan-and-deploy/hybrid-mode/)
- [Kong Helm Chart - Hybrid Mode](https://github.com/Kong/charts/blob/main/charts/kong/README.md#hybrid-mode)
- [Kong Documentation](https://docs.konghq.com/gateway/latest/)
