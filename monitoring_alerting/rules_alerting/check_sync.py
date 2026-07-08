#!/usr/bin/env python3
"""Check that the YAML and JSON provisioning trees carry identical alert rules.

The two subdirectories are identical by design (yaml_based_provisioning/ for
kubectl / ArgoCD / GUI import, json_based_provisioning/ for the Grafana API).
This script extracts (alert name, expr, for, severity) from both trees and
fails if they drifted apart.

Alerts are matched via the alert name: the `alert:` field in the YAML rules
and the `# Alert: <name>` header comment in each rule .env file. Annotations
are intentionally NOT compared - the two systems use different templating
syntaxes ({{ $value }} vs {{ $values.B }}).

Usage: python3 check_sync.py   (run from monitoring_alerting/rules_alerting/)
Exit code 0 = in sync, 1 = drift detected. No dependencies beyond stdlib.
"""
import glob
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
YAML_GLOB = os.path.join(HERE, "yaml_based_provisioning", "*.yaml")
ENV_GLOB = os.path.join(HERE, "json_based_provisioning", "rules", "*", "*.env")


def norm_expr(expr):
    return re.sub(r"\s+", " ", expr).strip()


def parse_yaml_rules():
    """Line-based parser for the constrained PrometheusRule format used here
    (single-line exprs, severity only under labels). Avoids a PyYAML dependency."""
    rules = defaultdict(list)  # name -> [(expr, for, severity, file)]
    for path in sorted(glob.glob(YAML_GLOB)):
        name = expr = for_ = sev = None

        def flush():
            if name is not None:
                rules[name].append((norm_expr(expr or ""), for_ or "", sev or "", os.path.basename(path)))

        for raw in open(path, encoding="utf-8"):
            line = raw.strip()
            if line.startswith("- alert:"):
                flush()
                name = line.split(":", 1)[1].strip()
                expr = for_ = sev = None
            elif name is not None and line.startswith("expr:"):
                expr = line.split(":", 1)[1].strip()
            elif name is not None and line.startswith("for:"):
                for_ = line.split(":", 1)[1].strip()
            elif name is not None and line.startswith("severity:"):
                sev = line.split(":", 1)[1].strip()
        flush()
    return rules


ENV_LINE = re.compile(r'''^(ALERT_EXPR|ALERT_FOR|ALERT_SEVERITY)=(?:'([^']*)'|"((?:[^"\\]|\\.)*)")''')


def parse_env_rules():
    rules = defaultdict(list)
    for path in sorted(glob.glob(ENV_GLOB)):
        name = None
        vals = {}
        for raw in open(path, encoding="utf-8"):
            line = raw.strip()
            m = re.match(r"^#\s*Alert:\s*(\S+)", line)
            if m:
                name = m.group(1)
                continue
            m = ENV_LINE.match(line)
            if m:
                key, sq, dq = m.groups()
                vals[key] = sq if sq is not None else dq.replace('\\"', '"')
        rel = os.path.relpath(path, HERE)
        if name is None:
            print(f"ERROR: {rel} has no '# Alert: <name>' header comment")
            sys.exit(1)
        rules[name].append((norm_expr(vals.get("ALERT_EXPR", "")),
                            vals.get("ALERT_FOR", ""),
                            vals.get("ALERT_SEVERITY", ""),
                            os.path.basename(path)))
    return rules


def main():
    yaml_rules = parse_yaml_rules()
    env_rules = parse_env_rules()
    drift = False

    for name in sorted(set(yaml_rules) - set(env_rules)):
        drift = True
        print(f"ONLY IN YAML: {name} ({', '.join(f for *_, f in yaml_rules[name])})")
    for name in sorted(set(env_rules) - set(yaml_rules)):
        drift = True
        print(f"ONLY IN ENV:  {name} ({', '.join(f for *_, f in env_rules[name])})")

    for name in sorted(set(yaml_rules) & set(env_rules)):
        # compare as multisets so duplicate alert names (e.g. GPUUnderutilized
        # at 15m and 30m) pair up regardless of file order
        y = sorted(t[:3] for t in yaml_rules[name])
        e = sorted(t[:3] for t in env_rules[name])
        if y != e:
            drift = True
            print(f"MISMATCH: {name}")
            for (expr, for_, sev), src in zip((t[:3] for t in sorted(yaml_rules[name])),
                                              (t[3] for t in sorted(yaml_rules[name]))):
                print(f"  yaml ({src}): expr={expr} | for={for_} | severity={sev}")
            for (expr, for_, sev), src in zip((t[:3] for t in sorted(env_rules[name])),
                                              (t[3] for t in sorted(env_rules[name]))):
                print(f"  env  ({src}): expr={expr} | for={for_} | severity={sev}")

    n_yaml = sum(len(v) for v in yaml_rules.values())
    n_env = sum(len(v) for v in env_rules.values())
    if drift:
        print(f"\nFAIL: YAML ({n_yaml} rules) and JSON ({n_env} rules) trees have drifted apart.")
        return 1
    print(f"OK: {n_yaml} YAML rules == {n_env} env rules (expr / for / severity all match)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
