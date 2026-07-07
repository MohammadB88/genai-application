# Improvement Suggestions — `monitoring_alerting/rules_alerting/`

Status: proposal (2026-07-07). Both subdirectories intentionally carry the identical rule
catalog: `yaml_based_provisioning/` for kubectl / ArgoCD / GUI import,
`json_based_provisioning/` for the Grafana provisioning API.

## 1. Alert & rule content (applies to both YAML and JSON forms)

- **[DONE 2026-07-07] Fix the NIM vLLM metric names — verified against vLLM/NIM docs.** NIM passes through
  vLLM's native metrics, and all of them use the `vllm:` prefix (colon, not underscore).
  The names currently in `nim_vllm.yaml` and `rules/nim-vllm/*.env` do not exist:

  | Current (wrong) | Correct (vLLM v1 engine) |
  |---|---|
  | `vllm_num_waiting_requests` | `vllm:num_requests_waiting` |
  | `vllm_request_duration_seconds_bucket` | `vllm:e2e_request_latency_seconds_bucket` |
  | `vllm_kv_cache_usage_perc` / `gpu_cache_usage_perc` | `vllm:kv_cache_usage_perc` (v0 engines: `vllm:gpu_cache_usage_perc`) |
  | `vllm_time_to_first_token_seconds_bucket` | `vllm:time_to_first_token_seconds_bucket` |
  | `vllm_num_preemptions_total` | `vllm:num_preemptions_total` |
  | `vllm_tokens_per_second_total` | no such metric — use `rate(vllm:generation_tokens_total[5m])` |
  | `vllm_gpu_memory_used_bytes / vllm_gpu_memory_total_bytes` | not exposed by vLLM — use DCGM: `DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)` |
  | `vllm_request_failure_total` | no such metric — derive from `vllm:request_success_total` by `finished_reason` label, or alert on HTTP 5xx at the gateway |

  As written, most NIM vLLM alerts can never fire. Final names should still be confirmed
  once against a live pod: `curl <nim-svc>:8000/v1/metrics`.

- **Rework the NIM TensorRT-LLM / embedding rules.** The NeMo Retriever Text Embedding NIM
  is Triton-based; it does not expose `trtllm_request_latency_ms_bucket`,
  `trtllm_request_failures_total`, or `embedding_requests_total`. Expect Triton metrics
  instead (`nv_inference_request_success`, `nv_inference_request_failure`,
  `nv_inference_request_duration_us`, `nv_inference_queue_duration_us`,
  `nv_gpu_utilization`, `nv_gpu_memory_used_bytes`). Rewrite the 5 rules against a live
  scrape of the embedding NIM (`:8000/v1/metrics`, Triton also on `:8002/metrics`); note
  Triton durations are in **microseconds**, so latency thresholds need converting.

- **Add label/value templating to annotations.** Descriptions are static text; include
  `{{ $labels.Hostname }}`, `{{ $labels.gpu }}`, `{{ $labels.pod }}`, `{{ $value }}` so a
  firing alert identifies the affected GPU/node/pod.

- **Scope `GPUNodeNotReady` to GPU nodes.** `kube_node_status_condition{condition="Ready",
  status="true"} == 0` matches every node in the cluster; join on a GPU node label
  (e.g. `* on(node) group_left kube_node_labels{label_nvidia_com_gpu_present="true"}`).

- **Fix `GPUUnhealthy`.** `DCGM_FI_DEV_GPU_TEMP < 0 or DCGM_FI_DEV_GPU_UTIL < 0` never
  fires — unhealthy GPUs make the metric disappear, not go negative. Use
  `absent(DCGM_FI_DEV_GPU_TEMP)` or rely on `DCGMExporterDown`.

- **Add `runbook_url` annotations** (even pointing at sections of `rules_alerts.md`) so
  receivers get a next step.

- **Make the YAML CRs OpenShift-aware.** `namespace: monitoring` + label
  `release: kube-prometheus-stack` targets a kube-prometheus-stack install. On OpenShift
  user-workload monitoring, PrometheusRules must live in the workload namespace and need
  no release label. Provide kustomize overlays (OpenShift UWM vs kube-prometheus-stack)
  or document the required edit.

- **Enforce YAML ↔ JSON parity mechanically.** Since the trees are identical by design,
  add a `check_sync.sh` (or CI step) that extracts `expr` / `for` / `severity` from both
  and diffs them, so a threshold changed on one side fails loudly.

- **Clean up the JSON template** (`templates/alert-rule.json.tmpl`):
  - The reduce/threshold stages are dead weight — every rule ships
    `THRESHOLD_OP="gt"` / `THRESHOLD_VALUE=-1` because the threshold is baked into
    `ALERT_EXPR`. Either drop stages B/C, or move thresholds into `THRESHOLD_VALUE`
    so they become editable in the Grafana GUI.
  - Prefer `"datasourceUid": "__expr__"` over the legacy `"-100"` for expression
    stages (both still work per Grafana docs, but `__expr__` is the current convention).
  - Make `orgID` configurable instead of hardcoded `1`.
  - Reconsider `noDataState: "OK"` for critical rules — it silences alerts exactly when
    metrics vanish; use `Alerting` or `NoData` for exporter-health-style rules.

## 2. Scripts (`json_based_provisioning/`)

- **Bug:** `cleaunup_all.sh` uses `set -u`, then tests `[[ -z "$GRAFANA_URL" ]]` — with the
  variable unset this aborts with "unbound variable", so the interactive-prompt path can
  never run. Use `${GRAFANA_URL:-}` / `${GRAFANA_TOKEN:-}`; add `-uo pipefail` to the
  deploy scripts too (they only have `set -e`).
- **Cleanup deletes ALL Grafana alert rules**, not just ones provisioned here — dangerous
  on a shared Grafana. Filter fetched rules by `folderUID == $GRAFANA_FOLDER_UID` (or the
  collected `ALERT_GROUPS`) before offering deletion; add `--yes` for non-interactive runs.
- **Replace the grep-based "rule exists" check** in the deploy scripts with
  `jq -r '.[] | select(.title==$t) | .uid'` — jq is already required by cleanup, and grep
  can mismatch when one title is a substring of another.
- **Consolidate the three near-identical deploy scripts** (they differ only in config file
  and rules dir) into one `deploy_rules.sh <gpu|nim-vllm|nim-tensorrtllm>|--all`, plus a
  shared `lib/common.sh` for the repeated GRAFANA_URL/TOKEN prompt block.
- **Add error handling to cleanup's curl calls** (`-sf` + exit-code check); a bad token
  currently yields an empty response and a misleading "No alert rules found."
- **Rename typo'd files:** `cleaunup_all.sh` → `cleanup_all.sh`,
  `rules_alers.md` → `rules_alerts.md` (update references).

## 3. README / docs

- **Fix `json_based_provisioning/README.md`:** it references `deploy-rule.sh` and
  `cleanup.sh`, which don't exist. Document the real scripts (or the consolidated one),
  the `GRAFANA_URL`/`GRAFANA_TOKEN` env-or-prompt behavior, and the required first steps:
  run `read_folders_datasources.sh` to obtain UIDs, then edit `config/global.env`
  (currently placeholder `your-folder-uid` / `your-prometheus-uid`).
- **Add a top-level `rules_alerting/README.md`** stating explicitly that both
  subdirectories carry the identical catalog and when to use each path
  (YAML → kubectl / ArgoCD / GUI import; JSON → Grafana provisioning API).
- **Update the metric tables in `rules_alers.md`** to the verified names above — the
  current tables mix invented names (`vllm:requests_per_second_total`,
  `trtllm:inference_duration_ms`) with real ones.
- Optionally add an ArgoCD `Application` under `gitops/` for `yaml_based_provisioning/`
  to make the ArgoCD path concrete.

## Sources

- [NIM for LLMs — Logging & Observability](https://docs.nvidia.com/nim/large-language-models/latest/reference/logging-and-observability.html) (NIM passes through vLLM's native metrics at `/v1/metrics`)
- [vLLM metrics design](https://docs.vllm.ai/en/latest/design/metrics.html) (exact `vllm:*` metric names, v0→v1 renames)
- [NeMo Retriever Text Embedding NIM — Observability](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/latest/observability.html) (Triton-based metrics)
- [Grafana Alerting Provisioning HTTP API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/alerting_provisioning/) and [file provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) (`__expr__` vs legacy `-100`)
