FROM python:3.12-slim

# Ensure Python output is unbuffered (important for Docker logs)
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY todo_app.py .

EXPOSE $PORT

CMD ["python", "todo_app.py", "$PORT"]
