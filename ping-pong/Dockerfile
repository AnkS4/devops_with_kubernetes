FROM python:3.12-slim

# Ensure Python output is unbuffered (important for Docker logs)
ENV PYTHONUNBUFFERED=1
ENV PORT=8002

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE $PORT

CMD sh -c "uvicorn app:app --host 0.0.0.0 --port ${PORT}"
