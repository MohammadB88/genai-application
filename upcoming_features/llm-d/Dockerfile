FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY src/gateway ./src/gateway

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "src.gateway.main:app", "--host", "0.0.0.0", "--port", "8000"]
