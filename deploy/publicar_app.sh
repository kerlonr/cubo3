#!/bin/sh
# Gera o APK assinado e o app web e publica no servidor do Cubo³. Rode da raiz do repositório (Git Bash).
# Precisa de app/android/key.properties + app/android/cubo3-release.jks (fora do git).
# Não usa sudo: as pastas dados/web e dados/apk são do usuário server. A API não precisa reiniciar.
set -eu
DESTINO=${DESTINO:-server@192.168.1.150}
FLUTTER=${FLUTTER:-D:/dev/flutter/bin/flutter.bat}
PASTA=projects/cubo3/dados

[ -f app/android/key.properties ] || { echo "Falta app/android/key.properties (assinatura do APK)"; exit 1; }

VERSAO=$(sed -n 's/^version: *\([^+]*\)+.*$/\1/p' app/pubspec.yaml)
BUILD=$(sed -n 's/^version: *[^+]*+\([0-9]*\).*$/\1/p' app/pubspec.yaml)
APK="cubo3-$VERSAO-$BUILD.apk"

(cd app && "$FLUTTER" build apk --release && "$FLUTTER" build web --release)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp app/build/app/outputs/flutter-apk/app-release.apk "$TMP/$APK"
printf '{"versao": "%s", "build": %s, "apk": "%s"}\n' "$VERSAO" "$BUILD" "$APK" > "$TMP/versao.json"

# App web: extrai numa pasta nova e sincroniza. A pasta web/ é montada no container (bind mount),
# então trocar o diretório com mv deixaria o container servindo o antigo; o index.html entra por último.
tar -C app/build/web -czf - . | ssh "$DESTINO" "set -e; cd ~/$PASTA; rm -rf web.novo; mkdir web.novo; tar -xzf - -C web.novo;
  rsync -a --delete --exclude index.html web.novo/ web/; cp web.novo/index.html web/index.html.tmp;
  mv web/index.html.tmp web/index.html; rm -rf web.novo"

# APK e versao.json (o versao.json por último: só anuncia a versão quando o APK já está lá).
tar -C "$TMP" -cf - "$APK" | ssh "$DESTINO" "set -e; tar -xf - -C ~/$PASTA/apk"
tar -C "$TMP" -cf - versao.json | ssh "$DESTINO" "set -e; cd ~/$PASTA/apk; tar -xf - -O versao.json > versao.json.tmp; mv versao.json.tmp versao.json"

echo "Publicado: web + $APK (build $BUILD)"
echo "Confira: curl -s https://cubo3.kerlonr.com.br/api/versao"
