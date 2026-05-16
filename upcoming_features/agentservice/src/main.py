from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from agentservice.src.agents.health_agent import create_system_health_agent
import os

app = FastAPI(title="GenAI Agent Service")

# Configurations from environment variables
MODEL_URL = os.getenv("MODEL_URL", "http://localhost:8000/v1")
API_KEY = os.getenv("MODEL_API_KEY", "no-key")

# Initialize agent
agent_executor = create_system_health_agent(MODEL_URL, API_KEY)

class QueryRequest(BaseModel):
    input: str
    chat_history: list = []

class QueryResponse(BaseModel):
    output: str

@app.post("/chat", response_model=QueryResponse)
async def chat(request: QueryRequest):
    try:
        # Convert simple list history to LangChain message objects if needed, 
        # but for first version we'll keep it simple
        result = agent_executor.invoke({
            "input": request.input,
            "chat_history": request.chat_history
        })
        return QueryResponse(output=result["output"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {"status": "healthy"}
