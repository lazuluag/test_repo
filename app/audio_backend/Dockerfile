FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY .env /app
COPY . /app

RUN mkdir -p /root/.oci

COPY .oci/config /root/.oci
COPY .oci/key.pem /root/.oci

CMD ["uvicorn", "audio_backend:app", "--host", "0.0.0.0", "--port", "8000"]