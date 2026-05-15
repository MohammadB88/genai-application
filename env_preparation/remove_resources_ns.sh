#!/bin/bash

# Fetch namespaces starting with "NS"
namespaces=$(oc get ns --no-headers -o custom-columns=":metadata.name" | grep '^ic-')

# Check if any namespaces were found
if [[ -z "$namespaces" ]]; then
  echo "No namespaces found starting with 'ic-'. Exiting."
  exit 0
fi

echo "The following namespaces will be deleted:"
echo "----------------------------------------"
echo "$namespaces"
echo "----------------------------------------"
echo

# Ask for confirmation
read -p "Do you want to proceed? (yes/no): " confirm

if [[ "$confirm" == "yes" ]]; then
  echo "Proceeding with deletion..."
elif [[ "$confirm" == "no" ]]; then
  echo "Operation aborted by user."
  exit 1
else
  echo "Invalid input. Please type 'yes' or 'no'. Aborting."
  exit 1
fi

# Ask for deletion method
echo "How would you like to remove the namespaces?"
echo "1) Delete all resources inside first, then delete the namespace"
echo "2) Delete the namespace directly (fastest, removes everything)"
read -p "Select an option (1/2): " method

if [[ "$method" == "1" ]]; then
  echo "Proceeding with resource-first deletion..."
  mode="cleanup"
elif [[ "$method" == "2" ]]; then
  echo "Proceeding with direct namespace deletion..."
  mode="direct"
else
  echo "Invalid selection. Aborting."
  exit 1
fi

# Loop through namespaces
for ns in $namespaces; do
  echo "Processing namespace: $ns"

  if [[ "$mode" == "cleanup" ]]; then
    echo "Cleaning up resources in $ns..."
    oc api-resources --verbs=list --namespaced -o name | while read resource; do
      oc delete "$resource" --all -n "$ns" --ignore-not-found
    done
  fi

  echo "Deleting namespace: $ns"
  oc delete namespace "$ns"

  echo "----------------------------------------"
done

echo "All done."
