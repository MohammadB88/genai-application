#!/usr/bin/env python3
"""
convert_prompts.py

Converts a custom prompts JSON array (list of objects with "prompt",
"max_tokens", etc.) into the JSONL format AIPerf's `random_pool`
dataset loader expects:

    {"text_input": "...", "output_length": 130}

Usage:
    python convert_prompts.py prompt.json prompts.jsonl

If the input contains duplicate "id" values, a warning is printed
(duplicates are still converted, just flagged).
"""

import json
import sys
from collections import Counter


def convert(input_path: str, output_path: str) -> None:
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        sys.exit(f"Error: expected a JSON array at the top level of {input_path}")

    ids = [item.get("id") for item in data if "id" in item]
    dupes = [k for k, v in Counter(ids).items() if v > 1]
    if dupes:
        print(f"Warning: duplicate 'id' values found (kept anyway): {dupes}", file=sys.stderr)

    written = 0
    with open(output_path, "w", encoding="utf-8") as out:
        for i, item in enumerate(data):
            prompt = item.get("prompt")
            if not prompt:
                print(f"Warning: skipping entry {i} (missing 'prompt')", file=sys.stderr)
                continue

            record = {"text_input": prompt}

            if "max_tokens" in item:
                record["output_length"] = item["max_tokens"]

            out.write(json.dumps(record, ensure_ascii=False) + "\n")
            written += 1

    print(f"Wrote {written} records to {output_path}")
    print(
        "Note: fields like 'language', 'category', 'temperature', and 'id' are not "
        "part of AIPerf's random_pool schema and were dropped. If you need a fixed "
        "temperature applied to every request, pass it once via:\n"
        "  --extra-inputs temperature:0.7"
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"Usage: python {sys.argv[0]} <input.json> <output.jsonl>")
    convert(sys.argv[1], sys.argv[2])
