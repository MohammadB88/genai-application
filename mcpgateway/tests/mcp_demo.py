import requests
import os

def run_mcp_demo():
    # Default endpoint, can be overridden via environment variable
    endpoint = os.getenv("MCP_ENDPOINT", "http://mcp-gateway.mcp.example.com")
    
    test_uris = [
        "milvus://search?query=ai-agents",
        "minio://docs-bucket/architecture.pdf",
        "invalid://something"
    ]
    
    print(f"Running MCP Demo against: {endpoint}\n")
    
    for uri in test_uris:
        print(f"Requesting URI: {uri}")
        try:
            response = requests.post(f"{endpoint}/resource", json={"uri": uri})
            if response.status_code == 200:
                print(f"Response: {response.json()}\n")
            else:
                print(f"Error: {response.status_code} - {response.text}\n")
        except Exception as e:
            print(f"Connection Error: {e}\n")

if __name__ == "__main__":
    run_mcp_demo()
