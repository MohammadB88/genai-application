# Alerting rules

Alert rules for the GPU/LLM-serving stack: GPU hardware health, GPU cost efficiency,
and serving-level SLOs for NIM vLLM and NIM TensorRT-LLM/embedding models. The full
catalog — metrics, expressions, `for`, severity — is documented in
[`rules_alerts.md`](rules_alerts.md).

## Two provisioning trees, one identical catalog

[`yaml_based_provisioning/`](yaml_based_provisioning/) and
[`json_based_provisioning/`](json_based_provisioning/) intentionally carry the **same
33 alert rules**. They're not alternatives to choose between once — they're two
delivery mechanisms for the same rules, kept in sync on purpose so you can pick
whichever fits how your Grafana/Prometheus is deployed:

| | `yaml_based_provisioning/` | `json_based_provisioning/` |
|---|---|---|
| Format | `PrometheusRule` CRs (`monitoring.coreos.com/v1`) | Grafana Alerting Provisioning API JSON, rendered from `.env` files |
| Deploy via | `kubectl apply -f ...`, ArgoCD `Application`, or paste into Grafana's "Import" GUI | Shell scripts calling `/api/v1/provisioning/alert-rules` directly |
| Use when | Prometheus Operator manages your alert rules (OpenShift user-workload monitoring, kube-prometheus-stack) | You provision Grafana-managed alerting directly, independent of a PrometheusRule CRD |
| Details | Read the YAML directly — no scripts needed | See [`json_based_provisioning/README.md`](json_based_provisioning/README.md) |

Because both trees carry the same rules, changing a threshold, expression, or `for`
duration on one side requires the same change on the other. Run
[`check_sync.py`](check_sync.py) after editing either tree to confirm they haven't
drifted apart:

```sh
python3 check_sync.py
```

It extracts `(alert name, expr, for, severity)` from both trees and diffs them,
matching rules by their alert name (the YAML `alert:` field vs. the `# Alert: <name>`
header comment in each `.env` file). Annotations aren't compared — the two systems use
different templating syntax (`{{ $value }}` in PrometheusRule vs. `{{ $values.B }}` in
the Grafana JSON template).

## Directory layout

```
rules_alerts.md                    Full alert catalog: metrics, expressions, for, severity
check_sync.py                      YAML <-> JSON parity checker (see above)
improvement_suggestions.md         Running list of proposed improvements and their status

yaml_based_provisioning/
  gpu_cluster_health.yaml          DCGMExporterDown, driver/toolkit/node readiness, XID errors (5)
  gpu_critical_rules.yaml          Memory/temp/power critical, XID detected, GPU unhealthy (5)
  gpu_warning_rules.yaml           Memory/temp/utilization/power warning thresholds (5)
  gpu_cost_efficiency.yaml         Underutilization, imbalance, idle-on-expensive-node (5)
  nim_vllm.yaml                    Latency, queue, KV cache, throughput, failures (8)
  nim_tensorrtllm.yaml             Embedding NIM (Triton) latency/throughput/failures (5)

json_based_provisioning/
  README.md                        Script usage, prerequisites, jq fallback
  config/                          global.env (folder/datasource/org UID) + per-topic env
  rules/{gpu,nim-vllm,nim-tensorrtllm}/   One .env file per alert rule
  templates/alert-rule.json.tmpl   Rendered via envsubst into the Grafana API payload
  deploy_rules_*.sh                Deploy scripts (jq-based; grep-fallback built in)
  deploy_rules_*_v0_grep.sh        Pinned grep-only variants for jq-less environments
  deploy_notification_policy.sh    Deploys a severity-routed notification policy tree
  cleanup_all.sh                   Folder-scoped rule/policy cleanup
  read_folders_datasources.sh      Lists Grafana folders/datasources to populate config/global.env
```

## Where to start

- **Just want to read what alerts exist?** → [`rules_alerts.md`](rules_alerts.md)
- **Deploying via kubectl/ArgoCD/GUI import?** → apply the YAML files in
  [`yaml_based_provisioning/`](yaml_based_provisioning/) directly
- **Deploying via the Grafana API?** → [`json_based_provisioning/README.md`](json_based_provisioning/README.md)
- **Changed a rule?** → update both trees, then run `python3 check_sync.py`
