FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py /app
COPY wallet /app/wallet
COPY utils  /app/utils
COPY services /app/services
COPY pages /app/pages
COPY my_component /app/my_component
COPY components /app/components
COPY images /app/images
COPY .env /app

RUN mkdir -p /root/.oci

COPY .oci/config /root/.oci
COPY .oci/key.pem /root/.oci

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]