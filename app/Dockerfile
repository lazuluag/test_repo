FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py /app
COPY wallet /app
COPY utils  /app
COPY services /app
COPY pages /app
COPY my_component /app
COPY components /app
COPY .env /app


CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]