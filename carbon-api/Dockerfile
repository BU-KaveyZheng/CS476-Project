FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY carbon_poller.py .

# Create cache directory
RUN mkdir -p /cache

ENV POLL_INTERVAL_MINUTES=5
ENV CACHE_TTL_MINUTES=10
ENV CACHE_FILE=/cache/carbon_cache.json

CMD ["python", "carbon_poller.py"]

