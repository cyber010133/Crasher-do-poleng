#!/bin/bash

# ======= COLOQUE SEU HTML AQUI =======
HTML="index.html"
# =====================================

C='\033[0;36m' G='\033[0;32m' R='\033[0;31m' N='\033[0m'

PORT=8080
while ss -tlnp 2>/dev/null | grep -q ":$PORT "; do ((PORT++)); done

DIR=$(dirname "$HTML")
FILE=$(basename "$HTML")

[[ ! -f "$HTML" ]] && echo -e "${R}Arquivo não encontrado: $HTML${N}" && exit 1

if [[ "$FILE" != "index.html" ]]; then
    cp "$HTML" "$DIR/index.html"
    trap "rm -f '$DIR/index.html'" EXIT
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G} Local : http://localhost:$PORT${N}"
echo -e "${G} Rede  : http://$IP:$PORT${N}"
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━${N}"

command -v termux-open-url &>/dev/null && sleep 1 && termux-open-url "http://localhost:$PORT" &
command -v xdg-open &>/dev/null && sleep 1 && xdg-open "http://localhost:$PORT" &>/dev/null &

cd "$DIR" && python3 -m http.server $PORT,