import requests
import time
import os

def run_batch_demo():
    endpoint = os.getenv("BATCH_ENDPOINT", "http://batch-processor.batch-processing.example.com")
    
    # 1. Submit a job
    payload = {
        "job_type": "embedding",
        "input_files": ["doc1.txt", "doc2.txt", "doc3.txt"],
        "model_name": "all-minilm-l6-v2",
        "params": {"chunk_size": 512}
    }
    
    print(f"Submitting batch job to: {endpoint}...")
    try:
        response = requests.post(f"{endpoint}/submit", json=payload)
        response.raise_for_status()
        job_id = response.json().get("job_id")
        print(f"Job submitted successfully! Job ID: {job_id}")
        
        # 2. Poll for status
        while True:
            status_res = requests.get(f"{endpoint}/status/{job_id}")
            status_data = status_res.json()
            print(f"Status: {status_data['status']} | Progress: {status_data['progress']}%")
            
            if status_data['status'] == 'completed':
                print(f"Job Finished! Results at: {status_data['result_path']}")
                break
            elif status_data['status'] == 'failed':
                print("Job failed.")
                break
                
            time.sleep(2)
            
    except Exception as e:
        print(f"Error during demo: {e}")

if __name__ == "__main__":
    run_batch_demo()
