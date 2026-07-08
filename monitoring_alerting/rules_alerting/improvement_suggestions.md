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

- **[DONE 2026-07-07] Rework the NIM TensorRT-LLM / embedding rules.** The NeMo Retriever Text Embedding NIM
  is Triton-based; it does not expose `trtllm_request_latency_ms_bucket`,
  `trtllm_request_failures_total`, or `embedding_requests_total`. Expect Triton metrics
  instead (`nv_inference_request_success`, `nv_inference_request_failure`,
  `nv_inference_request_duration_us`, `nv_inference_queue_duration_us`,
  `nv_gpu_utilization`, `nv_gpu_memory_used_bytes`). Rewrite the 5 rules against a live
  scrape of the embedding NIM (`:8000/v1/metrics`, Triton also on `:8002/metrics`); note
  Triton durations are in **microseconds**, so latency thresholds need converting.

- **[DONE 2026-07-07] Add label/value templating to annotations.** Descriptions are static text; include
  `{{ $labels.Hostname }}`, `{{ $labels.gpu }}`, `{{ $labels.pod }}`, `{{ $value }}` so a
  firing alert identifies the affected GPU/node/pod.

- **[DONE 2026-07-07] Scope `GPUNodeNotReady` to GPU nodes.** `kube_node_status_condition{condition="Ready",
  status="true"} == 0` matches every node in the cluster; join on a GPU node label
  (e.g. `* on(node) group_left kube_node_labels{label_nvidia_com_gpu_present="true"}`).

- **[DONE 2026-07-07] Fix `GPUUnhealthy`.** `DCGM_FI_DEV_GPU_TEMP < 0 or DCGM_FI_DEV_GPU_UTIL < 0` never
  fires — unhealthy GPUs make the metric disappear, not go negative. Use
  `absent(DCGM_FI_DEV_GPU_TEMP)` or rely on `DCGMExporterDown`.

- **[DONE 2026-07-07] Add `runbook_url` annotations** (even pointing at sections of `rules_alerts.md`) so
  receivers get a next step.

- **[ON HOLD] Make the YAML CRs OpenShift-aware.** `namespace: monitoring` + label
  `release: kube-prometheus-stack` targets a kube-prometheus-stack install. On OpenShift
  user-workload monitoring, PrometheusRules must live in the workload namespace and need
  no release label. Provide kustomize overlays (OpenShift UWM vs kube-prometheus-stack)
  or document the required edit.

- **[DONE 2026-07-08] Enforce YAML ↔ JSON parity mechanically.** Since the trees are
  identical by design, added [`check_sync.py`](check_sync.py) (stdlib-only, run from
  `rules_alerting/`) which extracts `expr` / `for` / `severity` per alert name from both
  trees and diffs them. First run caught real drift on 4 GPU rules (`GPUErrorsIncreasing`
  missing its `> 0` comparison and `for: 0s` instead of `0m`; `GPUMemoryCritical` at 0.98
  vs 0.95; `GPUMemoryHigh` at 0.95 vs 0.85; `GPUMemoryHighComputeLow` at 0.95 vs 0.80) —
  all fixed to match the YAML side, which was the source of truth. Now exits 0.

- **[DONE 2026-07-08] Clean up the JSON template** (`templates/alert-rule.json.tmpl`):
  - Reduce/threshold stages (B/C) kept — Grafana's provisioning API requires the rule
    `condition` to reference a reduced/thresholded expression, so they can't simply be
    dropped. Instead, `THRESHOLD_OP`/`THRESHOLD_VALUE` moved to defaults in
    `config/global.env` (`gt` / `-1`, documented inline) and removed from all 33 rule
    `.env` files — they're still overridable per-rule if a threshold is ever pulled out
    of `ALERT_EXPR` to make it GUI-editable.
  - `"datasourceUid": "-100"` → `"__expr__"` for both expression stages (B and C).
  - `orgID` is now `${ORGID}`, sourced from `config/global.env` (default `1`).
  - `noDataState: "OK"` left as-is for now — flagged but not changed in this pass;
    revisit per-rule if false negatives on exporter-down scenarios become a problem.

## 2. Scripts (`json_based_provisioning/`)

- **[DONE 2026-07-08] Bug:** `cleaunup_all.sh` uses `set -u`, then tests
  `[[ -z "$GRAFANA_URL" ]]` — with the variable unset this aborted with "unbound
  variable", so the interactive-prompt path could never run. Fixed to
  `${GRAFANA_URL:-}` / `${GRAFANA_TOKEN:-}` in `cleanup_all.sh` and all 3 deploy
  scripts; deploy scripts also upgraded from `set -e` to `set -euo pipefail`.
- **[DONE 2026-07-08] Cleanup deletes ALL Grafana alert rules**, not just ones
  provisioned here. Fixed: `cleanup_all.sh` now requires `GRAFANA_FOLDER_UID` to be
  set in `config/global.env` (refuses to run against the `your-folder-uid`
  placeholder) and filters fetched rules by `.folderUID == $GRAFANA_FOLDER_UID`
  via `jq` before offering deletion. Added `--yes` to skip the per-rule confirmation
  prompt for non-interactive/CI runs.
- **[DONE 2026-07-08] Replace the grep-based "rule exists" check** in the 3 deploy
  scripts with `jq -r --arg t "$ALERT_TITLE" '[.[] | select(.title == $t)] | .[0].uid // empty'`.
  Since `jq` is not guaranteed to be present on every environment (it's not in the
  POSIX base spec, unlike the cleanup script's pre-existing hard dependency), each
  script now checks `command -v jq` and falls back to the original grep matcher with
  a `[WARN]` if it's missing. The original grep-only versions are preserved unchanged
  as `deploy_rules_gpu_v0_grep.sh`, `deploy_rules_nim_vllm_v0_grep.sh`,
  `deploy_rules_nim_tensorrtllm_v0_grep.sh` for environments known not to have `jq`.
- **[ON HOLD] Consolidate the three near-identical deploy scripts** (they differ only
  in config file and rules dir) into one `deploy_rules.sh <gpu|nim-vllm|nim-tensorrtllm>|--all`,
  plus a shared `lib/common.sh` for the repeated GRAFANA_URL/TOKEN prompt block.
- **[DONE 2026-07-08] Add error handling to cleanup's curl calls** (`-sf` + exit-code
  check) — a bad token or unreachable Grafana now aborts with `[ERROR]` instead of
  silently yielding an empty response and "No alert rules found."
- **[DONE 2026-07-08] Rename typo'd files:** `cleaunup_all.sh` → `cleanup_all.sh`,
  `rules_alers.md` → `rules_alerts.md` (via `git mv`; all `runbook_url` references
  in the YAML rules and `.env` config files updated to match).

## 3. README / docs

- **[DONE 2026-07-08] Fix `json_based_provisioning/README.md`:** it referenced
  `deploy-rule.sh` and `cleanup.sh`, which don't exist. Rewrote to document the real
  scripts (`deploy_rules_gpu.sh`, `deploy_rules_nim_vllm.sh`,
  `deploy_rules_nim_tensorrtllm.sh`, `cleanup_all.sh`, plus the `_v0_grep.sh`
  fallbacks), the `GRAFANA_URL`/`GRAFANA_TOKEN` env-or-prompt behavior, and the
  required first steps (run `read_folders_datasources.sh`, then edit
  `config/global.env`).
- **[DONE 2026-07-08] Add a top-level `rules_alerting/README.md`** stating explicitly
  that both subdirectories carry the identical catalog and when to use each path
  (YAML → kubectl / ArgoCD / GUI import; JSON → Grafana provisioning API), plus a
  directory map and pointer to `check_sync.py`.
- **[DONE 2026-07-08] Update the metric tables in `rules_alerts.md`** to verified
  names. Beyond the vLLM/TensorRT-LLM fixes from earlier passes, a background
  verification agent checked the GPU table against NVIDIA's DCGM exporter source
  (`etc/default-counters.csv`, `dcgm-api-field-ids.html`) and found more problems:
  - The entire "Operator" category (`gpu_operator_gpu_nodes_total`,
    `gpu_operator_reconciliation_status`, `gpu_operator_driver_ready`, etc.) was
    **fabricated** — the GPU Operator doesn't expose a `gpu_operator_*` Prometheus
    endpoint; readiness is surfaced via `ClusterPolicy` CR status and node labels.
    Removed from the table (the actual `GPUDriverNotReady`/`GPUToolkitNotReady`
    alerts correctly use `kube_pod_container_status_ready`, which was never wrong).
  - `DCGM_FI_DEV_ECC_ERRORS` doesn't exist as a field — replaced with
    `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` / `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL`.
  - `DCGM_FI_DEV_PCIE_TX_THROUGHPUT` and `DCGM_FI_DEV_NVLink_THROUGHPUT` don't
    exist — replaced with `DCGM_FI_PROF_PCIE_TX_BYTES` and
    `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL`.
  - **`DCGM_FI_DEV_POWER_LIMIT` doesn't exist as a DCGM field** — this one wasn't
    just a doc error, it was used in 3 *live* alert expressions
    (`GPUPowerNearLimit`, `GPUPowerCritical`, `GPUPowerInefficient`) across both
    provisioning trees, meaning those alerts could never evaluate. Fixed to
    `DCGM_FI_DEV_POWER_MGMT_LIMIT` in all 6 rule files (3 YAML + 3 `.env`) and the
    doc table, with a comment noting it's not in dcgm-exporter's default counters
    and needs a custom counters file to actually populate. `check_sync.py` and the
    JSON-render validator both still pass after the fix.
  - The alert table was also stale relative to the actual rules (missing
    `IdleGPUOnExpensiveNode`, `GPUMemoryCritical`, `GPUTemperatureCritical`,
    `GPUPowerCritical`, `GPUXIDErrorDetected`, `GPUUnhealthy`; had a since-fixed
    `GPUImbalanceDetected` expression) — regenerated to match all 20 GPU rules.
- **[ON HOLD] Optionally add an ArgoCD `Application`** under `gitops/` for
  `yaml_based_provisioning/` to make the ArgoCD path concrete.

## Sources

- [NIM for LLMs — Logging & Observability](https://docs.nvidia.com/nim/large-language-models/latest/reference/logging-and-observability.html) (NIM passes through vLLM's native metrics at `/v1/metrics`)
- [vLLM metrics design](https://docs.vllm.ai/en/latest/design/metrics.html) (exact `vllm:*` metric names, v0→v1 renames)
- [NeMo Retriever Text Embedding NIM — Observability](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/latest/observability.html) (Triton-based metrics)
- [Grafana Alerting Provisioning HTTP API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/alerting_provisioning/) and [file provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) (`__expr__` vs legacy `-100`)
