#!/bin/sh
# Envia server/ e deploy/ para o servidor. Rode da raiz do repositório (Git Bash).
# Depois, no servidor: cd ~/projects/cubo3/deploy && sudo docker compose up -d --build
set -eu
DESTINO=${DESTINO:-server@192.168.1.150}

tar -czf - \
  --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache --exclude='*.db' --exclude=arquivos \
  --exclude=deploy/.env --exclude='deploy/tunnel/*.json' --exclude=deploy/tunnel/config.yml \
  server deploy \
  | ssh "$DESTINO" 'mkdir -p ~/projects/cubo3/dados/arquivos ~/projects/cubo3/dados/web ~/projects/cubo3/dados/apk ~/projects/cubo3/dados/backups && tar -xzf - -C ~/projects/cubo3'

echo "Enviado. No servidor: cd ~/projects/cubo3/deploy && sudo docker compose up -d --build"
