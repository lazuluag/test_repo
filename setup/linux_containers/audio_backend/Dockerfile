FROM python:3.11-slim

WORKDIR /app

COPY audio_backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY audio_backend/services /app
COPY .env /app
COPY audio_backend/audio_backend.py /app


CMD ["uvicorn", "audio_backend:app", "--host", "0.0.0.0", "--port", "8000"]