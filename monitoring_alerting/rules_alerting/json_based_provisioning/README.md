# JSON-based provisioning (Grafana Alerting Provisioning API)

Provisions the alert rules in `rules/` straight into Grafana via
`/api/v1/provisioning/alert-rules`, by rendering each rule's `.env` file through
[`templates/alert-rule.json.tmpl`](templates/alert-rule.json.tmpl). This is the same
rule catalog as [`../yaml_based_provisioning/`](../yaml_based_provisioning/) — use this
path when you're talking to Grafana's API directly rather than deploying
`PrometheusRule` CRs via kubectl/ArgoCD/GUI import. See
[`../rules_alerts.md`](../rules_alerts.md) for the full alert catalog and the metrics
each one is based on.

## Prerequisites

1. **Grafana connection.** Every script prompts for `GRAFANA_URL` and `GRAFANA_TOKEN`
   (a Grafana service account token with alerting provisioning permissions) if they
   aren't already set in the environment:
   ```sh
   export GRAFANA_URL="https://grafana.example.com"
   export GRAFANA_TOKEN="glsa_xxxxxxxx"
   ```
2. **Folder UID and datasource UID.** Run `read_folders_datasources.sh` once against
   your Grafana instance to list available folders and Prometheus datasources:
   ```sh
   ./read_folders_datasources.sh
   ```
3. **Edit `config/global.env`.** Set the values you got from step 2 — the shipped
   values are placeholders and deploys will go to the wrong folder/datasource (or
   `cleanup_all.sh` will refuse to run) if left unset:
   ```sh
   GRAFANA_FOLDER_UID="<folder-uid-from-step-2>"
   DATASOURCE_UID="<prometheus-datasource-uid-from-step-2>"
   ```
   `ORGID` and the `THRESHOLD_OP`/`THRESHOLD_VALUE` defaults in `global.env` normally
   don't need to change — see the comments in that file.
4. **`jq`** is required by `cleanup_all.sh`. The deploy scripts prefer `jq` too (for
   the rule-exists check) but fall back to a `grep`-based check with a warning if
   `jq` isn't installed — see "No `jq`?" below.

## Deploying rules

Each topic has its own deploy script, config file (`config/<topic>.env`, which sets
`ALERT_GROUP` and `ALERT_RUNBOOK_URL`), and rules directory:

| Topic | Deploy script | Config | Rules dir |
|---|---|---|---|
| GPU cluster health / critical / warning / cost efficiency (20 rules) | `deploy_rules_gpu.sh` | `config/gpu.env` | `rules/gpu/` |
| NIM vLLM (8 rules) | `deploy_rules_nim_vllm.sh` | `config/nim_vllm.env` | `rules/nim-vllm/` |
| NIM TensorRT-LLM / embedding (5 rules) | `deploy_rules_nim_tensorrtllm.sh` | `config/nim_tensorrtllm.env` | `rules/nim-tensorrtllm/` |

```sh
# Deploy a single rule
./deploy_rules_gpu.sh rules/gpu/gpu-temperature-critical.env

# Deploy every rule for a topic
./deploy_rules_gpu.sh --all
./deploy_rules_nim_vllm.sh --all
./deploy_rules_nim_tensorrtllm.sh --all
```

Deploys are idempotent: each script looks up the rule by title and does a `PUT`
(update) if it already exists, or a `POST` (create) if it doesn't. The rendered JSON
is validated (`python3 -m json.tool`) before it's sent.

## Deploying the notification policy

```sh
./deploy_notification_policy.sh
```

This replaces the entire Grafana notification policy tree (it's a `PUT`) with a
simple severity-based routing tree. Edit the script directly to change receivers or
routing — see the comments at the top of the file.

## Cleanup

```sh
./cleanup_all.sh --rules     # Delete alert rules in GRAFANA_FOLDER_UID only
./cleanup_all.sh --policy    # Reset notification policy to Grafana default
./cleanup_all.sh --all       # Both
./cleanup_all.sh --rules --yes   # Same, but skip the per-rule confirmation prompt
```

No flag defaults to `--rules`. Deletion is scoped to `GRAFANA_FOLDER_UID` from
`config/global.env` — it will not touch rules provisioned elsewhere in your Grafana
instance, and refuses to run at all if `GRAFANA_FOLDER_UID` is still the placeholder
value. Without `--yes`, you're prompted per rule before it's deleted.

## No `jq`?

`deploy_rules_gpu.sh`, `deploy_rules_nim_vllm.sh`, and `deploy_rules_nim_tensorrtllm.sh`
each check for `jq` and fall back to a `grep`-based title match if it's missing,
printing a `[WARN]`. If you'd rather skip the `jq` check entirely (e.g. your
environment is guaranteed not to have it), use the pinned `grep`-only variants
instead — same usage, same flags:

```sh
./deploy_rules_gpu_v0_grep.sh --all
./deploy_rules_nim_vllm_v0_grep.sh --all
./deploy_rules_nim_tensorrtllm_v0_grep.sh --all
```

`cleanup_all.sh` has a hard dependency on `jq` (folder-scoped filtering and UID/title
parsing) and has no grep fallback — install `jq` to use it.

## Rule count by topic

| Directory | Rules |
|---|---|
| `rules/gpu/` | GPU cluster health (5), critical (5), warning (5), cost efficiency (5) — 20 total |
| `rules/nim-vllm/` | 8 |
| `rules/nim-tensorrtllm/` | 5 |
