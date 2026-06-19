# AIPerf

## Run Convertor
python convert_prompts.py prompt.json prompts.jsonl 

## RUN TEST
# Pass via env vars
MODEL=my-model URL=http://localhost:8000 ./run_aiperf_sustained.sh

# Or just run it and get prompted
./run_aiperf_sustained.sh

# Optional
Temperatur can be added in the test run: --extra-inputs temperature:0.7

