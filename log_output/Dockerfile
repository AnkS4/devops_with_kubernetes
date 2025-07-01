FROM python:3.12-slim

# Ensure Python output is unbuffered (important for Docker logs)
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY app.py .

CMD ["python", "app.py"]
