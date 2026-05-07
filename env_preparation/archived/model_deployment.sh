#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="argocd"

echo "=== Argo CD Deployment Helper ==="

# Ask user if Argo CD exists
read -p "Do you already have an Argo CD instance installed? (y/n): " argocd_exists

if [[ "$argocd_exists" == "y" ]]; then
  echo "Using existing Argo CD instance."

elif [[ "$argocd_exists" == "n" ]]; then
  echo "Argo CD is not installed. We will deploy models directly using kustomization"

  echo "*********************************************"
  # Ask user to select model deployment target
  models=("ollama" "nvidia_nim" "vllm")
  default=0

  echo "Select model deployment target:"
  for i in "${!models[@]}"; do
      echo "  $i) ${models[$i]}"
  done

  read -p "Enter choice [${default}]: " model_choice
  model_choice=${model_choice:-$default}

  if ! [[ "$model_choice" =~ ^[0-9]+$ ]] || (( model_choice < 0 || model_choice >= ${#models[@]} )); then
      echo "Invalid choice, using default: ${models[$default]}"
      model_choice=$default
  fi
  CUSTOM_PATH="../models/${models[$model_choice]}"


  echo "*********************************************"
  echo "Applying kustomization..."
  oc apply -k "$CUSTOM_PATH"

  echo "Model deployment triggered."

else
  echo "Skipping model deployment."
fi

echo "=== Done ==="