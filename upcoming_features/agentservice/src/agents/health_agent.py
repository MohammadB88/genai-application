import os
from typing import List, Dict
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_openai_tools_agent
from langchain_core.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

# --- Tools ---
@tool
def get_cluster_cpu_usage() -> str:
    \"\"\"Returns the current CPU usage of the cluster. Use this for health checks.\"\"\"
    # Mocking the actual OC/K8s API call for the first version
    return "CPU Usage: 45% (Normal). Peaks at 60% in namespace 'llms'."

@tool
def get_cluster_memory_usage() -> str:
    \"\"\"Returns the current memory usage of the cluster. Use this for health checks.\"\"\"
    # Mocking the actual OC/K8s API call for the first version
    return "Memory Usage: 72% (Warning). Some pods in 'nvidia-nim' are nearing limits."

@tool
def get_pod_status(namespace: str) -> str:
    \"\"\"Returns status of pods in a specific namespace. Input should be the namespace name.\"\"\"
    # Mocking the actual OC/K8s API call
    mock_data = {
        "llms": "All pods Running.",
        "agents": "1 pod Pending, 2 pods Running.",
        "mcp": "All pods Running."
    }
    return mock_data.get(namespace, "Namespace not found or no pods available.")

# --- Agent Setup ---
def create_system_health_agent(model_url: str, api_key: str = "no-key"):
    llm = ChatOpenAI(
        model="gpt-4-turbo", # Default, can be overridden
        openai_api_base=model_url,
        openai_api_key=api_key,
        temperature=0
    )
    
    tools = [get_cluster_cpu_usage, get_cluster_memory_usage, get_pod_status]
    
    prompt = ChatPromptTemplate.from_messages([
        ("system", "You are a System Health Agent. Your job is to monitor the OpenShift cluster and provide concise health reports using the tools provided."),
        MessagesPlaceholder(variable_name="chat_history"),
        ("human", "{input}"),
        MessagesPlaceholder(variable_name="agent_scratchpad"),
    ])
    
    agent = create_openai_tools_agent(llm, tools, prompt)
    return AgentExecutor(agent=agent, tools=tools, verbose=True)
