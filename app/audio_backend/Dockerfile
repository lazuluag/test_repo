FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY .env /app
COPY . /app

RUN mkdir -p /root/.oci

COPY /home/opc/.oci/config /root/.oci/config
COPY /home/opc/.oci/key.pem /root/.oci/key.pem

CMD ["uvicorn", "audio_backend:app", "--host", "0.0.0.0", "--port", "8000"]