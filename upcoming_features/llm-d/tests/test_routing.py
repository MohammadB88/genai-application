import requests
import os

def test_routing():
    endpoint = os.getenv("LLMD_ENDPOINT", "http://llm-d-gateway.llm-d.example.com")
    
    test_cases = [
        {
            "name": "Short Prompt",
            "prompt": "Hi!",
            "expected_route": "NIM"
        },
        {
            "name": "Long Prompt",
            "prompt": "Please provide a detailed technical analysis of the distributed inference architecture including the role of the KV cache, prefill and decode phases, and how token-aware routing improves overall throughput across multiple GPU nodes.",
            "expected_route": "vLLM"
        }
    ]
    
    print(f"Testing llm-d Routing at: {endpoint}\n")
    
    for case in test_cases:
        print(f"--- Testing {case['name']} ---")
        try:
            # Using the debug endpoint to verify routing decision without needing real backend pods
            res = requests.get(f"{endpoint}/route-debug", params={"prompt": case['prompt']})
            res.raise_for_status()
            decision = res.json()
            print(f"Prompt: {case['prompt'][:50]}...")
            print(f"Decision: {decision['reason']}")
            print(f"Endpoint: {decision['endpoint']}")
            
            # Check if routing logic matches expectations
            if case['expected_route'].lower() in decision['endpoint'].lower():
                print("Result: SUCCESS ✅")
            else:
                print("Result: FAIL ❌")
        except Exception as e:
            print(f"Error: {e}")
        print("\n")

if __name__ == "__main__":
    test_routing()
