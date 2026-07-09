# Environment Preparations

Deploy/cleanup scripts for the platform components. Shared helpers (colors, `oc`/`kubectl`
detection, namespace utilities) live in [common.sh](common.sh).

## Model deployment (`models_deploy.sh`)

Deploys any model directory under `models/` that contains a `kustomization.yaml`.
The target namespace is read from the model's `kustomization.yaml`.

```sh
# Interactive: pick model, storage class, and enter credentials when prompted
./models_deploy.sh

# Semi-interactive: model preselected
./models_deploy.sh nvidia_nim/llama321b

# Fully automatic (CI / unattended)
NGC_API_KEY=nvapi-... STORAGE_CLASS=ocs-external-storagecluster-ceph-rbd \
  ./models_deploy.sh nvidia_nim/llama321b -y
```

Options and environment variables:

| Name | Purpose |
|---|---|
| `-y`, `--non-interactive` | Never prompt; fail if required input is missing |
| `--timeout <seconds>` | Readiness wait per deployment (default 1800) |
| `NGC_API_KEY` | NGC key for `nvidia_nim/*` models (creates `ngc-api-key` + `nim-pull-secret`) |
| `HUGGING_FACE_HUB_TOKEN` | HF token for `vllm/gpu/*` models (creates `huggingface-secret`) |
| `STORAGE_CLASS` | Storage class for model PVCs; `default` = cluster default |

Behavior notes:

- **GPU preflight**: if the model requests `nvidia.com/gpu`, the script checks that at
  least one node reports allocatable GPUs. In non-interactive mode a GPU-less cluster
  aborts the deployment; interactively you can choose to continue.
- **Secrets are created in-cluster only** (`kubectl create secret ... --dry-run=client | apply`).
  The `secret.yaml` files in the model directories are templates and are never modified.
  If the secrets already exist in the target namespace, credential input is skipped entirely.
- **Manifests are never mutated**: the model directory is copied to a temp dir, the
  storage class is patched there, and the temp copy is applied. `git status` stays clean.
- **Readiness = model serves**: the script waits with `rollout status` on exactly the
  deployments it applied. NIM/vLLM deployments carry startup/readiness probes on their
  health endpoints, so "ready" means the model answers requests — first-time GPU
  deployments can take 20+ minutes (image pull + weight download).

## Model cleanup (`models_cleanup.sh`)

```sh
# Interactive selection
./models_cleanup.sh

# Delete specific models without prompts
./models_cleanup.sh nvidia_nim/llama321b -y

# Delete everything, including the credential secrets
./models_cleanup.sh --all -y
```

Deletion is scoped to each model's namespace and waits (`--wait --timeout=120s`) only for
the resources of the deleted kustomizations. With `--all`, the credential secrets
(`ngc-api-key`, `nim-pull-secret`, `huggingface-secret`) are removed too (after a prompt,
or automatically with `-y`).

## GitOps (`argocd_deploy.sh` / `argocd_cleanup.sh`)

`argocd_deploy.sh` optionally bootstraps the `llms` namespace secrets and applies
`gitops/root-application.yaml`, then waits for the Argo CD application to become
synced/healthy.

## Other components

- `postgresql_deploy.sh` — PostgreSQL
- `monitoring_deploy.sh` / `monitoring_cleanup.sh` — Grafana + alerting rules
- `web_interfaces_deploy.sh` / `web_interfaces_cleanup.sh` — AnythingLLM
- `litemaas_deploy.sh` / `litemaas_cleanup.sh` — LiteMaaS gateway
- `remove_resources_argocd.sh`, `remove_resources_ns.sh` — bulk removal helpers
