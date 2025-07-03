FROM python:3.12-slim

# Ensure Python output is unbuffered (important for Docker logs)
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

WORKDIR /app

COPY todo_app.py .

# Copy requirements first for better caching
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the port
EXPOSE ${PORT}

# Run the application
CMD ["uvicorn", "todo_app:app", "--host", "0.0.0.0", "--port", "${PORT}"]
