# Builder stage for both images
FROM python:3.12-slim AS base

# Common environment variables
ENV PYTHONUNBUFFERED=1

# Create shared directory
RUN mkdir -p /app/shared

# Build generator image
FROM base AS generator
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY log_generator.py .
CMD ["python", "log_generator.py"]

# Build status image
FROM base AS status
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY log_status.py .
CMD ["uvicorn", "log_status:app", "--host", "0.0.0.0", "--port", "8002"]
