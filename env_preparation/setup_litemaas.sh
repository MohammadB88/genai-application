#!/bin/bash

# Step 1: Install Helm on RHEL 9.7
echo "Installing Helm on RHEL 9.7..."

# For RHEL, install Helm via binary download
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "Helm installed successfully."

# Step 2: Clone the repository
echo "Cloning the repository..."
git clone https://github.com/rh-aiservices-bu/litemaas.git
# cd litemaas

# Step 3: Use users.sh to create users
echo "Creating users using users.sh..."
# Use users.sh from the workspace ai-gateways/litemaas/
chmod +x ../ai-gateways/litemaas/users.sh
../ai-gateways/litemaas/users.sh

# Step 4: Find OpenShift cluster URL
echo "Finding OpenShift cluster URL..."
# Assuming oc is installed and configured
if command -v oc &> /dev/null; then
    CLUSTER_URL=$(oc get route -n openshift-console console -o jsonpath='{.spec.host}' | sed 's|console-openshift-console\.||')
    echo "Cluster URL: $CLUSTER_URL"
else
    echo "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Additional steps: Ask for OAUTH_CLIENT_SECRET and generate random numbers
echo "Enter OAUTH_CLIENT_SECRET:"
read OAUTH_CLIENT_SECRET

OPENSSL_RAND_NR=$(openssl rand -base64 16)
OPENSSL_RAND_NR_LITELM_MASTER_KEY=$(openssl rand -base64 16)

echo "Generated OPENSSL_RAND_NR: $OPENSSL_RAND_NR"
echo "Generated OPENSSL_RAND_NR_LITELM_MASTER_KEY: $OPENSSL_RAND_NR_LITELM_MASTER_KEY"

# Step 5: Use oauthclient.yaml with CLUSTER_URL and OAUTH_CLIENT_SECRET
echo "Applying oauthclient.yaml with CLUSTER_URL and OAUTH_CLIENT_SECRET..."
# Use oauthclient.yaml from the workspace ai-gateways/litemaas/
export CLUSTER_URL
export OAUTH_CLIENT_SECRET
envsubst < ../ai-gateways/litemaas/oauthclient.yaml | oc apply -f -

# Substitute variables in values_oc.yaml
echo "Substituting variables in values_oc.yaml..."
export OPENSSL_RAND_NR
export OPENSSL_RAND_NR_LITELM_MASTER_KEY
envsubst < ../ai-gateways/litemaas/values_oc.yaml > values_final.yaml
echo "Final values file created: values_final.yaml"

# Create namespace and install LiteMaaS using Helm
echo "Creating namespace litemaas..."
oc new-project litemaas

echo "Installing LiteMaaS using Helm..."
helm install litemaas deployment/helm/litemaas/ -n litemaas -f values_final.yaml

echo "Script completed."