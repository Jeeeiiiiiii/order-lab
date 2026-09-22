FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api.py .

EXPOSE 8080
# api.py writes its own JSON access log, so gunicorn's is left off.
CMD gunicorn --bind "0.0.0.0:${PORT:-8080}" --workers 2 api:app
