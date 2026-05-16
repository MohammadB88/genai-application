import os
import requests
import json
from typing import List

def test_agent_endpoint(endpoint_url: str, test_queries: List[str]):
    """
    Tests the deployed System Health Agent via its REST API.
    """
    print(f"Testing Agent at: {endpoint_url}")
    
    for i, query in enumerate(test_queries):
        print(f"\nTest {i+1}: {query}")
        payload = {
            "input": query,
            "chat_history": []
        }
        
        try:
            response = requests.post(f"{endpoint_url}/chat", json=payload)
            response.raise_for_status()
            result = response.json()
            print(f"Agent Response: {result.get('output')}")
        except Exception as e:
            print(f"Error occurred: {e}")

if __name__ == "__main__":
    # The user will provide this endpoint after deployment
    AGENT_ENDPOINT = os.getenv("AGENT_ENDPOINT", "http://system-health-agent.agents.example.com")
    
    queries = [
        "How is the cluster health overall?",
        "Check the CPU and memory usage.",
        "What is the status of pods in the llms namespace?",
        "Are there any issues in the agents namespace?"
    ]
    
    test_agent_endpoint(AGENT_ENDPOINT, queries)
