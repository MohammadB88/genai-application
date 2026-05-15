from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from mcpgateway.src.handlers.resource_manager import MCPResourceManager

app = FastAPI(title="MCP Gateway Service")
resource_manager = MCPResourceManager()

class MCPRequest(BaseModel):
    uri: str

class MCPResponse(BaseModel):
    uri: str
    content: any

@app.post("/resource", response_model=MCPResponse)
async def get_resource(request: MCPRequest):
    """
    Standardized MCP endpoint to retrieve a resource via URI.
    """
    result = resource_manager.resolve(request.uri)
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    
    return MCPResponse(uri=request.uri, content=result["data"])

@app.get("/health")
async def health():
    return {"status": "healthy"}
