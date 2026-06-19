#!/usr/bin/env bash
#
# run_aiperf_sustained.sh
#
# Runs an AIPerf "sustained average workload" benchmark:
#   - fixed concurrency (steady number of in-flight requests)
#   - fixed 20-minute duration
#   - prompts sampled randomly from a JSONL file (random_pool dataset)
#
# MODEL and URL are read from environment variables if set, otherwise
# the script will prompt for them interactively.
#
# Usage:
#   MODEL=my-model URL=http://localhost:8000 ./run_aiperf_sustained.sh
#   ./run_aiperf_sustained.sh                 # will prompt for both
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-prompts.jsonl}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-20}"
DURATION_SECONDS="${DURATION_SECONDS:-1200}"   # 20 minutes
WARMUP_REQUESTS="${WARMUP_REQUESTS:-10}"
RANDOM_SEED="${RANDOM_SEED:-42}"

# ---- Get MODEL: env var, else prompt ----------------------------------------
if [ -z "${MODEL:-}" ]; then
    read -r -p "Enter model name (--model): " MODEL
fi

# ---- Get URL: env var, else prompt ------------------------------------------
if [ -z "${URL:-}" ]; then
    read -r -p "Enter endpoint URL (--url), e.g. http://localhost:8000: " URL
fi

if [ -z "$MODEL" ] || [ -z "$URL" ]; then
    echo "Error: MODEL and URL must both be set." >&2
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: input file '$INPUT_FILE' not found." >&2
    echo "Set INPUT_FILE=/path/to/prompts.jsonl to override." >&2
    exit 1
fi

echo "----------------------------------------"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE"
echo "Concurrency:  $CONCURRENCY"
echo "Duration:     ${DURATION_SECONDS}s"
echo "----------------------------------------"

aiperf profile \
    --model "$MODEL" \
    --url "$URL" \
    --endpoint-type "$ENDPOINT_TYPE" \
    --endpoint "$ENDPOINT_PATH" \
    --streaming \
    --input-file "$INPUT_FILE" \
    --custom-dataset-type random_pool \
    --dataset-sampling-strategy random \
    --concurrency "$CONCURRENCY" \
    --benchmark-duration "$DURATION_SECONDS" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED"
