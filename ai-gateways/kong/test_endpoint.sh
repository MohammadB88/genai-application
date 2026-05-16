#!/bin/bash

KONG_PROXY="kong-proxy-kong.apps.cluster-fq6cl.fq6cl.sandbox2576.opentlc.com"
KONG_ROUTE="granite"
Model_NAME="granite-3-1-8b-instruct"

curl https://${KONG_PROXY}/${KONG_ROUTE}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "${MODEL_NAME}",
    "messages": [
      { "role": "user", "content": "Say hello in one sentence" }
    ]
  }'