from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
import time
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("batchprocessor")

app = FastAPI(title="GenAI Batch Processor")

# In-memory job store for the first version (will be replaced by DB/MinIO in future)
jobs_db = {}

class BatchJobRequest(BaseModel):
    job_type: str # 'embedding' or 'inference'
    input_files: List[str] # Paths to files in MinIO
    model_name: str
    params: Optional[dict] = {}

class JobStatus(BaseModel):
    job_id: str
    status: str
    progress: float
    result_path: Optional[str] = None

def run_batch_task(job_id: str, request: BatchJobRequest):
    """
    Simulates a batch processing job.
    In a real version, this would trigger a Kubernetes Job or Celery worker.
    """
    logger.info(f"Starting job {job_id} of type {request.job_type}")
    jobs_db[job_id] = {"status": "running", "progress": 0.0, "result_path": None}
    
    try:
        for i, file in enumerate(request.input_files):
            # Simulate processing time per file
            time.sleep(1) 
            progress = ((i + 1) / len(request.input_files)) * 100
            jobs_db[job_id]["progress"] = progress
            logger.info(f"Job {job_id}: Processing {file} ({progress:.1f}%)")
        
        # Finalize job
        result_path = f"s3://batch-output/{job_id}/results.json"
        jobs_db[job_id].update({"status": "completed", "progress": 100.0, "result_path": result_path})
        logger.info(f"Job {job_id} completed. Results at {result_path}")
        
    except Exception as e:
        logger.error(f"Job {job_id} failed: {e}")
        jobs_db[job_id]["status"] = "failed"

@app.post("/submit", response_model=JobStatus)
async def submit_job(request: BatchJobRequest, background_tasks: BackgroundTasks):
    job_id = str(uuid.uuid4())
    jobs_db[job_id] = {"status": "pending", "progress": 0.0, "result_path": None}
    
    background_tasks.add_task(run_batch_task, job_id, request)
    
    return JobStatus(job_id=job_id, status="pending", progress=0.0)

@app.get("/status/{job_id}", response_model=JobStatus)
async def get_status(job_id: str):
    if job_id not in jobs_db:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs_db[job_id]
    return JobStatus(job_id=job_id, status=job["status"], progress=job["progress"], result_path=job["result_path"])

@app.get("/health")
async def health():
    return {"status": "healthy"}
