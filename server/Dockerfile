FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
COPY requirements.txt requirements-dev.txt ./
# pytest entra na imagem para rodar a suíte contra o Postgres do próprio servidor
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
RUN useradd -u 1000 -m cubo && mkdir -p /dados/arquivos && chown -R cubo /dados /srv
USER 1000
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'"]
