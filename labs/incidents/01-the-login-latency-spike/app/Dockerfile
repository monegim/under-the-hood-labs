FROM python:3.11-slim

WORKDIR /opt/app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py worker.py ./

# Command is overridden per-service in docker-compose.yml (app vs worker).
CMD ["python3", "app.py"]
