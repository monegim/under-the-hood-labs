FROM python:3.11-slim

RUN apt-get update -qq && apt-get install -y -qq iputils-ping curl >/dev/null && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

CMD ["python3", "app.py"]
