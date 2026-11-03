#!/bin/sh
# Backup diário: dump do Postgres (guarda 30 dias) + espelho dos arquivos enviados.
# Os arquivos têm nome único e nunca são alterados, então o espelho só copia os novos
# (e mantém os que foram apagados no app, por segurança).
set -eu

until pg_isready -q; do sleep 2; done
mkdir -p /backups/banco /backups/arquivos

while true; do
  dia=$(date +%Y%m%d)
  if pg_dump -Fc -f "/backups/banco/cubo3-$dia.dump.tmp"; then
    mv "/backups/banco/cubo3-$dia.dump.tmp" "/backups/banco/cubo3-$dia.dump"
    echo "$(date) backup do banco ok"
  else
    echo "$(date) FALHA no pg_dump" >&2
  fi
  cp -an /arquivos/. /backups/arquivos/ && echo "$(date) espelho de arquivos ok"
  find /backups/banco -name 'cubo3-*.dump' -mtime +30 -delete
  sleep 86400
done
