FROM python:3.12-slim AS base

# Common environment variables
ENV PYTHONUNBUFFERED=1

# Create shared directory
RUN mkdir -p /app/shared

# Build main app image
FROM base AS main
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ templates/

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8001"]

# Build backend app image
FROM base AS backend
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app_backend.py .

CMD ["uvicorn", "app_backend:app", "--host", "0.0.0.0", "--port", "8003"]
