# Kong AI Gateway Deployment Guide

This directory contains Helm chart files for deploying Kong AI Gateway on OpenShift/Kubernetes. Kong AI Gateway provides advanced AI capabilities including prompt engineering, semantic caching, comprehensive observability, and enterprise-grade traffic management.

## Directory Structure

```
ai-gateways/kong/
├── Chart.yaml              # Helm chart definition
├── values.yaml             # Default configuration values
├── values-openshift.yaml   # OpenShift-specific configuration overrides
├── templates/              # Kubernetes manifest templates
│   ├── deployment.yaml     # Kong Gateway deployment
│   ├── service.yaml        # Kong Gateway service
│   ├── route.yaml          # OpenShift route for external access
│   └── servicemonitor.yaml # Prometheus ServiceMonitor for metrics collection
└── test-connectivity.sh    # Script to verify deployment
```

## Prerequisites

1. **OpenShift/Kubernetes Cluster**: Access to an OpenShift 4.x+ or Kubernetes 1.21+ cluster
2. **Helm 3.x**: Install Helm following the [official guide](https://helm.sh/docs/intro/install/)
3. **kubectl/oc CLI**: Configured to communicate with your cluster
4. **Container Registry Access**: Ability to pull images from Kong's official repositories
5. **Namespace**: Create or have access to a target namespace (e.g., `kong`)

## Deployment Instructions

### Step 1: Add Kong Helm Repository (if needed)

The chart is designed to work as a local chart, but if you prefer to use Kong's official repository:

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

Deploy using the provided values files, with OpenShift-specific overrides:

```bash
# Using Helm with local chart
helm install kong ./ai-gateways/kong \
  --namespace kong \
  -f ai-gateways/kong/values.yaml \
  -f ai-gateways/kong/values-openshift.yaml

# OR using Kong's official repository (if added)
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

### Default Values (`values.yaml`)
Contains standard Kong configuration including:
- Image version and repository
- Resource requests/limits
- Plugin configurations
- Admin API settings
- Proxy configuration

### OpenShift Overrides (`values-openshift.yaml`)
Contains OpenShift-specific adjustments:
- SecurityContext configurations for OpenShift restrictions
- ServiceAccount setup
- Route-specific configurations
- OpenShift-compatible readiness/liveness probes

### Custom Configuration
To customize your deployment, create a custom values file:

```bash
# Create custom-values.yaml with your overrides
helm install kong ./ai-gateways/kong \
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
- **AI Gateway Plugins**: Prompt engineering, semantic caching, request/response transformation
- **Observability**: Built-in Prometheus metrics via ServiceMonitor
- **OpenShift Integration**: Secure routes, proper security contexts
- **High Availability**: Configurable replica counts
- **Extensibility**: Easy to add additional plugins via values.yaml

## Troubleshooting

### Common Issues

1. **Image Pull Errors**: Ensure your cluster can access Kong's container registry
2. **Security Context Conflicts**: Adjust values in `values-openshift.yaml` if needed
3. **Route Creation Issues**: Verify OpenShift router is configured and accessible
4. **Port Conflicts**: Check that ports 8000 (proxy), 8443 (admin), and 8100 (status) are available

### Logs and Debugging

```bash
# View Kong pod logs
oc logs -f deployment/kong -n kong

# Describe problematic resources
oc describe pod <pod-name> -n kong
oc describe service kong-proxy -n kong
oc describe route kong-proxy -n kong
```

## Upgrading

To upgrade your Kong deployment:

```bash
helm upgrade kong ./ai-gateways/kong \
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
- [Kong Helm Chart](https://github.com/Kong/charts/tree/main/charts/kong)
- [Kong AI Gateway Documentation](https://docs.konghq.com/gateway/latest/ai-gateway/)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/4.14/authentication/managing-security-context-constraints.html)
