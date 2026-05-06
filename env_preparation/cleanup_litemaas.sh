#!/bin/bash

# Cleanup script to reverse changes made by setup_litemaas.sh

echo "Starting cleanup..."

# Step 1: Uninstall the Helm chart
echo "Uninstalling LiteMaaS Helm chart..."
helm uninstall litemaas -n litemaas

# Step 2: Delete the namespace
echo "Deleting namespace litemaas..."
oc delete project litemaas

# Step 3: Delete the OAuthClient
echo "Deleting OAuthClient litemaas..."
oc delete oauthclient litemaas

# # Step 4: Remove the cloned repository
# echo "Removing cloned repository..."
# rm -rf litemaas/

# Step 5: Remove the generated values file
echo "Removing generated values file..."
rm -f values_final.yaml

# Note: Helm installation and user creation from users.sh are not automatically reversed.
# - Helm binary remains installed; remove manually if desired.
# - Users created by users.sh need to be deleted manually or via additional scripts.

echo "Cleanup completed."