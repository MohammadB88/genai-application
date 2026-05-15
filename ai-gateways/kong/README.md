# Kong AI Gateway Deployment Guide (Using Official Helm Chart)

This directory contains configuration files for deploying the official Kong AI Gateway Helm chart on OpenShift/Kubernetes. 
We use the official Kong chart (`kong/kong`) with custom values files to tailor the deployment to our environment.

## Directory Structure

```
ai-gateways/kong/
├── values.yaml             # Custom configuration values for the official Kong chart
├── values-openshift.yaml   # OpenShift-specific configuration overrides
├── test-connectivity.sh    # Script to verify deployment
└── README.md               # This file
```

> **Note**: We use the official Kong Helm chart from `https://charts.konghq.com`. The local Chart.yaml and templates have been removed.

## Prerequisites

1. **OpenShift/Kubernetes Cluster**: Access to an OpenShift 4.x+ or Kubernetes 1.21+ cluster
2. **Helm 3.x**: Install Helm following the [official guide](https://helm.sh/docs/intro/install/)
3. **kubectl/oc CLI**: Configured to communicate with your cluster
4. **Container Registry Access**: Ability to pull images from Kong's official repositories
5. **Namespace**: Create or have access to a target namespace (e.g., `kong`)

## Deployment Instructions

### Step 1: Add Kong Helm Repository

```bash
helm repo add kong https://charts.konghq.com
helm repo update
```

### Step 2: Create Namespace (if not exists)

```bash
# Using oc (OpenShift)
oc new-project kong

# Or using kubectl
kubectl create namespace kong
```

### Step 3: Deploy Kong AI Gateway

Deploy using the official Kong chart with our custom values files:

```bash
helm install kong kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values.yaml \
  -f ai-gateways/kong/values-openshift.yaml
```

### Step 4: Verify Deployment

Check that all resources are created successfully:

```bash
# Check pods
oc get pods -n kong

# Check services
oc get svc -n kong

# Check routes (OpenShift)
oc get routes -n kong

# Check the ServiceMonitor for metrics
oc get servicemonitor -n kong
```

### Step 5: Test Connectivity

Run the provided connectivity test script:

```bash
chmod +x ai-gateways/kong/test-connectivity.sh
./ai-gateways/kong/test-connectivity.sh
```

## Configuration

### Custom Values (`values.yaml`)
Contains our custom configuration for the official Kong chart, including:
- Image version and repository
- Resource requests/limits
- Enabled plugins (currently only prometheus)
- Kong environment variables (database: "off", KONG_PLUGINS: prometheus)

### OpenShift Overrides (`values-openshift.yaml`)
Contains OpenShift-specific adjustments:
- Service type set to ClusterIP
- SecurityContext configurations for OpenShift restrictions

### Custom Configuration
To further customize your deployment, create a custom values file:

```bash
helm install kong kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values.yaml \
  -f ai-gateways/kong/values-openshift.yaml \
  -f custom-values.yaml
```

## Accessing Kong

### Admin API
Access Kong's Admin API for configuration:
```
https://<kong-route-host>/admin
```

### Proxy Endpoint
Use this endpoint for AI traffic:
```
https://<kong-route-host>
```

### Metrics Endpoint
Prometheus metrics are available at:
```
https://<kong-route-host>/metrics
```

## Features Enabled

This deployment includes:
- **Prometheus Plugin**: For metrics collection
- **OpenShift Integration**: Secure routes, proper security contexts
- **High Availability**: Configurable replica counts (default: 1)

## Troubleshooting

### Common Issues

1. **Image Pull Errors**: Ensure your cluster can access Kong's container registry
2. **Security Context Conflicts**: Adjust values in `values-openshift.yaml` if needed
3. **Route Creation Issues**: Verify OpenShift router is configured and accessible
4. **Port Conflicts**: Check that ports 8000 (proxy), 8443 (admin), and 8100 (status) are available

### Logs and Debugging

```bash
# View Kong pod logs
oc logs -f deployment/<release-name>-kong -n kong

# Describe problematic resources
oc describe pod <pod-name> -n kong
oc describe service <release-name>-kong-proxy -n kong
oc describe route <release-name>-kong-proxy -n kong
```

## Upgrading

To upgrade your Kong deployment:

```bash
helm upgrade kong kong/kong \
  --namespace kong \
  -f ai-gateways/kong/values.yaml \
  -f ai-gateways/kong/values-openshift.yaml
```

## Uninstalling

To remove Kong from your cluster:

```bash
helm uninstall kong --namespace kong
# Optionally delete the namespace
oc delete project kong
```

## References

- [Kong Documentation](https://docs.konghq.com/gateway/latest/)
- [Kong Helm Chart](https://artifacthub.io/packages/helm/kong/kong)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/4.14/authentication/managing-security-context-constraints.html)
