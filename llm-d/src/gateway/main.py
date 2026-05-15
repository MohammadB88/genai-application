import os
import httpx
import asyncio
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any

app = FastAPI(title="llm-d Inference Gateway (IGW)")

# Mock Routing Table - In a real scenario, this would come from a ConfigMap or K8s API
# We route based on a simple "token-aware" logic:
# Short prompts (< 100 chars) -> Optimized for low latency (NIM)
# Long prompts (>= 100 chars) -> Optimized for throughput (vLLM)
ROUTING_CONFIG = {
    "short_prompt_endpoint": os.getenv("NIM_ENDPOINT", "http://nim-service.llms.svc.cluster.local"),
    "long_prompt_endpoint": os.getenv("VLLM_ENDPOINT", "http://vllm-service.llms.svc.cluster.local"),
}

class RouteDecision(BaseModel):
    endpoint: str
    reason: str

def decide_route(prompt: str) -> RouteDecision:
    """
    Simple Token-Aware Routing Logic.
    For Phase 1, we use character length as a proxy for token count.
    """
    length = len(prompt)
    if length < 100:
        return RouteDecision(endpoint=ROUTING_CONFIG["short_prompt_endpoint"], reason="Short prompt: routed to low-latency NIM")
    else:
        return RouteDecision(endpoint=ROUTING_CONFIG["long_prompt_endpoint"], reason="Long prompt: routed to high-throughput vLLM")

@app.post("/v1/chat/completions")
async def proxy_chat(request: Request):
    """
    Inference Gateway proxy that implements token-aware routing.
    """
    body = await request.json()
    messages = body.get("messages", [])
    if not messages:
        raise HTTPException(status_code=400, detail="No messages provided")
    
    # Extract the last user prompt for routing decision
    user_prompt = messages[-1].get("content", "")
    decision = decide_route(user_prompt)
    
    print(f"llm-d IGW Decision: {decision.reason} -> {decision.endpoint}")

    # Forward the request to the chosen backend
    async with httpx.AsyncClient() as client:
        try:
            # Proxy the request exactly as it came in to the backend
            response = await client.post(
                f"{decision.endpoint}/v1/chat/completions",
                json=body,
                timeout=60.0
            )
            return response.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Backend error: {str(e)}")

@app.get("/health")
async def health():
    return {"status": "healthy", "routing": "active"}

@app.get("/route-debug")
async def debug_route(prompt: str):
    """Endpoint to test routing logic without calling a real model"""
    return decide_route(prompt)
