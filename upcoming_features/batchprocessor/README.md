# Batch Processor Service

This service handles large-scale LLM data tasks, such as generating embeddings for thousands of documents or batch inference across multiple prompts.

## Features
- **Asynchronous Processing**: Submit jobs and poll for status.
- **Task Types**: Supports `embedding` (text $\rightarrow$ vectors) and `inference` (prompts $\rightarrow$ text).
- **Progress Tracking**: Real-time progress updates for long-running jobs.

## Architecture
- **Engine**: FastAPI with `BackgroundTasks` (first version).
- **Storage**: Results are simulated as being written to MinIO (`s3://batch-output/`).
- **Deployment**: Deployed in the `batch-processing` namespace on OpenShift.

## Deployment

### 1. Build and Push Image
```bash
docker build -t batch-processor:latest -f batchprocessor/Dockerfile .
docker push <your-registry>/batch-processor:latest
```

### 2. Deploy to OpenShift
```bash
oc apply -f batchprocessor/k8s/manifests.yaml
```

## Usage

### Submitting a Job
**Request:**
```bash
curl -X POST http://<batch-route>/submit \
-H "Content-Type: application/json" \
-d '{
  "job_type": "embedding",
  "input_files": ["doc1.txt", "doc2.txt"],
  "model_name": "all-minilm-l6-v2"
}'
```

### Checking Status
**Request:**
```bash
curl http://<batch-route>/status/<job_id>
```

### Running the Demo
```bash
export BATCH_ENDPOINT=http://<your-batch-route>
python batchprocessor/tests/demo.py
```
